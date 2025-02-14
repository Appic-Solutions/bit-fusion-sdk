use bridge_did::error::BTFResult;
use bridge_did::op_id::OperationId;
use bridge_did::operation_log::{Memo, OperationLog};
use bridge_did::operations::Erc20BridgeOp;
use bridge_utils::common::Pagination;
use did::H160;
use ic_canister_client::{CanisterClient, CanisterClientResult};

use crate::bridge_client::BridgeCanisterClient;

pub struct Erc20BridgeClient<C> {
    client: C,
}

impl<C: CanisterClient> Erc20BridgeClient<C> {
    pub fn new(client: C) -> Self {
        Self { client }
    }

    /// Retrieves all operations for the given ETH wallet address whose
    /// id is greater than or equal to `min_included_id` if provided.
    /// The operations are then paginated with the given `pagination` parameters,
    /// starting from `offset` returning a max of `count` items
    /// If `offset` is `None`, it starts from the beginning (i.e. the first entry is the min_included_id).
    /// If `count` is `None`, it returns all operations.
    pub async fn get_operations_list(
        &self,
        wallet_address: &H160,
        min_included_id: Option<OperationId>,
        pagination: Option<Pagination>,
    ) -> CanisterClientResult<Vec<(OperationId, Erc20BridgeOp)>> {
        self.client
            .query(
                "get_operations_list",
                (wallet_address, min_included_id, pagination),
            )
            .await
    }

    pub async fn get_operation_log(
        &self,
        operation_id: OperationId,
    ) -> CanisterClientResult<Option<OperationLog<Erc20BridgeOp>>> {
        self.client
            .query("get_operation_log", (operation_id,))
            .await
    }

    pub async fn get_operation_by_memo_and_user(
        &self,
        memo: Memo,
        user_id: &H160,
    ) -> CanisterClientResult<Option<(OperationId, Erc20BridgeOp)>> {
        self.client
            .query("get_operation_by_memo_and_user", (memo, user_id))
            .await
    }

    pub async fn get_memos_by_user_address(
        &self,
        user_id: &H160,
    ) -> CanisterClientResult<Vec<Memo>> {
        self.client
            .query("get_memos_by_user_address", (user_id,))
            .await
    }

    pub async fn set_base_btf_bridge_contract(&self, address: &H160) -> CanisterClientResult<()> {
        self.client
            .update("set_base_btf_bridge_contract", (address,))
            .await
    }

    pub async fn get_bridge_canister_base_evm_address(
        &self,
    ) -> CanisterClientResult<BTFResult<H160>> {
        self.client
            .update("get_bridge_canister_base_evm_address", ())
            .await
    }
}

impl<C: CanisterClient> BridgeCanisterClient<C> for Erc20BridgeClient<C> {
    fn client(&self) -> &C {
        &self.client
    }
}
