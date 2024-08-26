use std::path::PathBuf;

use candid::Principal;
use clap::Parser;
use ic_canister_client::agent::identity::GenericIdentity;
use ic_utils::interfaces::management_canister::builders::InstallMode;
use ic_utils::interfaces::ManagementCanister;
use tracing::info;

#[derive(Debug, Parser)]
pub struct UpgradeCommands {
    #[arg(long, value_name = "CANISTER_ID")]
    canister_id: Principal,

    /// The path to the wasm file to deploy
    #[arg(long, value_name = "WASM_PATH")]
    wasm: PathBuf,
}

impl UpgradeCommands {
    pub async fn upgrade_canister(&self, identity: PathBuf, url: &str) -> anyhow::Result<()> {
        info!("Upgrading canister with ID: {}", self.canister_id.to_text());

        let canister_wasm = std::fs::read(&self.wasm)?;

        let identity = GenericIdentity::try_from(identity.as_ref())?;

        let agent = ic_agent::Agent::builder()
            .with_url(url)
            .with_identity(identity)
            .build()?;

        let management_canister = ManagementCanister::create(&agent);

        management_canister
            .install(&self.canister_id, &canister_wasm)
            .with_mode(InstallMode::Upgrade(None))
            .call_and_wait()
            .await?;

        info!("Canister upgraded successfully");

        Ok(())
    }
}
