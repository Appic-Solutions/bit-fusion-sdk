#![allow(async_fn_in_trait)]

use bridge_did::error::BftResult;
use bridge_did::op_id::OperationId;
use bridge_utils::bft_events::{BurntEventData, MintedEventData, NotifyMinterEventData};
use bridge_utils::evm_bridge::EvmParams;
use bridge_utils::evm_link::EvmLink;
use candid::CandidType;
use did::H160;
use eth_signer::sign_strategy::TransactionSigner;
use ic_task_scheduler::task::TaskOptions;
use serde::{Deserialize, Serialize};

pub trait Operation:
    Sized + CandidType + Serialize + for<'de> Deserialize<'de> + Clone + Send + Sync + 'static
{
    async fn progress(self, id: OperationId, ctx: impl OperationContext) -> BftResult<Self>;
    fn is_complete(&self) -> bool;

    /// Address of EVM wallet to/from which operation will move tokens.
    fn evm_address(&self) -> H160;

    fn scheduling_options(&self) -> Option<TaskOptions> {
        Some(TaskOptions::default())
    }

    async fn on_wrapped_token_minted(
        _ctx: impl OperationContext,
        _event: MintedEventData,
    ) -> Option<OperationAction<Self>> {
        None
    }

    async fn on_wrapped_token_burnt(
        _ctx: impl OperationContext,
        _event: BurntEventData,
    ) -> Option<OperationAction<Self>> {
        None
    }

    async fn on_minter_notification(
        _ctx: impl OperationContext,
        _event: NotifyMinterEventData,
    ) -> Option<OperationAction<Self>> {
        None
    }
}

pub trait OperationContext {
    fn get_evm_link(&self) -> EvmLink;
    fn get_bridge_contract_address(&self) -> BftResult<H160>;
    fn get_evm_params(&self) -> BftResult<EvmParams>;
    fn get_signer(&self) -> BftResult<impl TransactionSigner>;
}

pub enum OperationAction<Op> {
    Create(Op),
    Update { nonce: u32, update_to: Op },
}
