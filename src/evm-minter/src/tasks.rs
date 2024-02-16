use std::cell::RefCell;
use std::future::Future;
use std::pin::Pin;
use std::rc::Rc;

use ethereum_json_rpc_client::EthGetLogsParams;
use ethers_core::abi::RawLog;
use ethers_core::types::Log;
use ic_stable_structures::CellStructure;
use ic_task_scheduler::retry::BackoffPolicy;
use ic_task_scheduler::scheduler::TaskScheduler;
use ic_task_scheduler::task::{ScheduledTask, Task, TaskOptions};
use ic_task_scheduler::SchedulerError;
use minter_contract_utils::bft_bridge_api::{
    BurntEventData, MintedEventData, BURNT_EVENT, MINTED_EVENT,
};
use minter_contract_utils::BridgeSide;
use minter_did::id256::Id256;
use minter_did::order::MintOrder;
use serde::{Deserialize, Serialize};

use crate::canister::get_state;
use crate::state::State;

#[derive(Debug, Serialize, Deserialize)]
pub enum BridgeTask {
    InitEvmState(BridgeSide),
    CollectEvmEvents(BridgeSide),
    PrepareMintOrder(BurntEventData, BridgeSide),
    RemoveMintOrder(MintedEventData),
}

impl Task for BridgeTask {
    fn execute(
        &self,
        scheduler: Box<dyn 'static + TaskScheduler<Self>>,
    ) -> Pin<Box<dyn Future<Output = Result<(), SchedulerError>>>> {
        let state = get_state();
        match self {
            BridgeTask::InitEvmState(side) => Box::pin(Self::init_evm_state(state, *side)),
            BridgeTask::CollectEvmEvents(side) => {
                Box::pin(Self::collect_evm_events(state, scheduler, *side))
            }
            BridgeTask::PrepareMintOrder(data, side) => {
                Box::pin(Self::prepare_mint_order(state, data.clone(), *side))
            }
            BridgeTask::RemoveMintOrder(data) => {
                Box::pin(Self::remove_mint_order(state, data.clone()))
            }
        }
    }
}

impl BridgeTask {
    pub fn into_scheduled(self, options: TaskOptions) -> ScheduledTask<Self> {
        ScheduledTask::with_options(self, options)
    }

    pub async fn init_evm_state(
        state: Rc<RefCell<State>>,
        side: BridgeSide,
    ) -> Result<(), SchedulerError> {
        Self::init_evm_chain_id(state.clone(), side).await?;
        Self::init_evm_next_block(state, side).await?;

        log::trace!("evm state initialized for side {:?}", side);

        Ok(())
    }

    pub async fn init_evm_chain_id(
        state: Rc<RefCell<State>>,
        side: BridgeSide,
    ) -> Result<(), SchedulerError> {
        log::trace!("initializing evm chain id for side {:?}", side);

        let link = {
            let state = state.borrow();
            let info = state.config.get_evm_info(side);

            // If chain id is already set, there is nothing to do.
            // WARN: Changing chain id in runtime may lead to funds loss.
            if info.chain_id.is_some() {
                return Ok(());
            }

            info.link
        };

        let chain_id = match link
            .get_client()
            .get_chain_id()
            .await
            .into_scheduler_result()
        {
            Ok(id) => id,
            Err(e) => {
                log::error!("failed to get chain id: {e}");
                return Err(e);
            }
        };

        state.borrow_mut().config.set_evm_chain_id(chain_id, side);
        Ok(())
    }

    pub async fn init_evm_next_block(
        state: Rc<RefCell<State>>,
        side: BridgeSide,
    ) -> Result<(), SchedulerError> {
        log::trace!("initializing evm next block for side {:?}", side);
        let link = {
            let state = state.borrow();
            let info = state.config.get_evm_info(side);

            // If next block is already set, there is nothing to do.
            // WARN: Re-initializing next block in runtime may lead to funds loss.
            if info.next_block.is_some() {
                return Ok(());
            }

            info.link
        };

        let next_block = link
            .get_client()
            .get_block_number()
            .await
            .into_scheduler_result()?;
        state
            .borrow_mut()
            .config
            .set_evm_next_block(next_block, side);
        Ok(())
    }

    async fn collect_evm_events(
        state: Rc<RefCell<State>>,
        scheduler: Box<dyn 'static + TaskScheduler<Self>>,
        side: BridgeSide,
    ) -> Result<(), SchedulerError> {
        log::trace!("collecting evm events: side: {side:?}");

        let Some(evm_info) = state.borrow().config.get_initialized_evm_info(side) else {
            log::warn!("failed to collect events for side {side:?}: evm info is not initialized",);
            return Self::init_evm_state(state, side).await;
        };

        let client = evm_info.link.get_client();

        let params = EthGetLogsParams {
            address: Some(vec![evm_info.bridge_contract.into()]),
            from_block: evm_info.next_block.into(),
            to_block: ethers_core::types::BlockNumber::Safe,
            topics: Some(vec![vec![
                BURNT_EVENT.signature(),
                MINTED_EVENT.signature(),
            ]]),
        };

        log::debug!("collecting logs from side {side:?} with params: {params:?}");

        let logs = match client.get_logs(params).await.into_scheduler_result() {
            Ok(logs) => logs,
            Err(e) => {
                log::error!("failed to get logs: {e}");
                return Err(e);
            }
        };

        log::debug!("got logs from side {side:?}: {logs:?}");

        let mut mut_state = state.borrow_mut();

        // Filter out logs that do not have block number.
        // Such logs are produced when the block is not finalized yet.
        let last_log = logs.iter().take_while(|l| l.block_number.is_some()).last();
        if let Some(last_log) = last_log {
            let next_block_number = last_log.block_number.unwrap().as_u64() + 1;
            mut_state.config.set_evm_next_block(next_block_number, side);
            log::trace!("updated evm next block for side {side:?}: {next_block_number}");
        };

        log::trace!("appending logs to tasks: {side:?}: {logs:?}");

        scheduler.append_tasks(
            logs.into_iter()
                .filter_map(|l| Self::task_by_log(l, side))
                .collect(),
        );

        Ok(())
    }

    async fn prepare_mint_order(
        state: Rc<RefCell<State>>,
        burn_event: BurntEventData,
        sender_side: BridgeSide,
    ) -> Result<(), SchedulerError> {
        log::trace!("preparing mint order: {burn_event:?}");
        let recipient = Id256::from_slice(&burn_event.recipient_id)
            .and_then(|id| id.to_evm_address().ok())
            .ok_or_else(|| {
                log::error!("failed to decode recipient data: {burn_event:?}");
                SchedulerError::TaskExecutionFailed("failed to decode recipient data".into())
            })?
            .1;

        let dst_token = Id256::from_slice(&burn_event.to_token)
            .and_then(|id| id.to_evm_address().ok())
            .unwrap_or_default()
            .1;

        let sender_chain_id = state
            .borrow()
            .config
            .get_initialized_evm_info(sender_side)
            .ok_or_else(|| {
                log::error!("sender evm info is not initialized: {sender_side:?}");
                SchedulerError::TaskExecutionFailed("sender evm info is not initialized".into())
            })?
            .chain_id as u32;

        let recipient_chain_id = state
            .borrow()
            .config
            .get_initialized_evm_info(sender_side.other())
            .ok_or_else(|| {
                log::error!("recipient evm info is not initialized: {sender_side:?}");
                SchedulerError::TaskExecutionFailed("recipient evm info is not initialized".into())
            })?
            .chain_id as u32;

        let sender = Id256::from_evm_address(&burn_event.sender, sender_chain_id);
        let src_token = Id256::from_evm_address(&burn_event.from_erc20, sender_chain_id);

        fn to_array<const N: usize>(data: &[u8]) -> Result<[u8; N], SchedulerError> {
            data.try_into().into_scheduler_result()
        }

        let nonce = burn_event.operation_id;

        let mint_order = MintOrder {
            amount: burn_event.amount,
            sender,
            src_token,
            recipient,
            dst_token,
            nonce,
            sender_chain_id,
            recipient_chain_id,
            name: to_array(&burn_event.name)?,
            symbol: to_array(&burn_event.symbol)?,
            decimals: burn_event.decimals,
        };

        let signer = state.borrow().signer.get().clone();
        let signed_mint_order = mint_order
            .encode_and_sign(&signer)
            .await
            .into_scheduler_result()?;

        state
            .borrow_mut()
            .mint_orders
            .insert(sender, src_token, nonce, &signed_mint_order);

        log::trace!("Mint order added");

        Ok(())
    }

    fn task_by_log(log: Log, sender_side: BridgeSide) -> Option<ScheduledTask<BridgeTask>> {
        log::trace!("creating task from the log: {log:?}");

        let raw_log = RawLog {
            topics: log.topics,
            data: log.data.to_vec(),
        };

        const TASK_RETRY_DELAY_SECS: u32 = 5;

        let options = TaskOptions::default()
            .with_backoff_policy(BackoffPolicy::Fixed {
                secs: TASK_RETRY_DELAY_SECS,
            })
            .with_max_retries_policy(u32::MAX);

        match BurntEventData::try_from(raw_log.clone()) {
            Ok(burnt_event_data) => {
                log::debug!("Adding PrepareMintOrder task");
                let mint_order_task = BridgeTask::PrepareMintOrder(burnt_event_data, sender_side);
                return Some(mint_order_task.into_scheduled(options));
            }
            Err(e) => log::debug!("Failed to decode BurntEventData: {e}"),
        }

        match MintedEventData::try_from(raw_log) {
            Ok(mint_event_data) => {
                log::debug!("Adding RemoveMintOrder task");
                let remove_mint_order_task = BridgeTask::RemoveMintOrder(mint_event_data);
                return Some(remove_mint_order_task.into_scheduled(options));
            }
            Err(e) => log::debug!("Failed to decode MintedEventData: {e}"),
        }

        None
    }

    async fn remove_mint_order(
        state: Rc<RefCell<State>>,
        minted_event: MintedEventData,
    ) -> Result<(), SchedulerError> {
        let sender_id = Id256::from_slice(&minted_event.sender_id).ok_or_else(|| {
            SchedulerError::TaskExecutionFailed(
                "failed to decode sender id256 from minted event".into(),
            )
        })?;

        let src_token = Id256::from_slice(&minted_event.from_token).ok_or_else(|| {
            SchedulerError::TaskExecutionFailed(
                "failed to decode token id256 from minted event".into(),
            )
        })?;

        state
            .borrow_mut()
            .mint_orders
            .remove(sender_id, src_token, minted_event.nonce);

        log::trace!("Mint order removed");

        Ok(())
    }
}

trait IntoSchedulerError {
    type Success;

    fn into_scheduler_result(self) -> Result<Self::Success, SchedulerError>;
}

impl<T, E: ToString> IntoSchedulerError for Result<T, E> {
    type Success = T;

    fn into_scheduler_result(self) -> Result<Self::Success, SchedulerError> {
        self.map_err(|e| SchedulerError::TaskExecutionFailed(e.to_string()))
    }
}
