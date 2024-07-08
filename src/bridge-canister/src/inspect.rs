use ic_exports::ic_cdk::api;
use ic_storage::IcStorage;

use crate::BridgeCore;

pub fn bridge_inspect() {
    let core = BridgeCore::get();
    let core = core.borrow();
    let method = api::call::method_name();

    match method.as_str() {
        "set_logger_filter" => core.inspect_set_logger_filter(),
        "ic_logs" => core.inspect_ic_logs(),
        "set_owner" => core.inspect_set_owner(),
        "set_evm_principal" => core.inspect_set_evm_principal(),
        "set_bft_bridge_contract" => core.inspect_set_bft_bridge_contract(),
        _ => {}
    }
}
