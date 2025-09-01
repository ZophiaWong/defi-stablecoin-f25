## unit test for `DSCEngine.sol`

- Minting DSC:
  - Test that minting 0 DSC reverts.
  - Test that minting DSC works as expected.
  - Test that minting DSC reverts if the health factor breaks.
- Burning DSC:
  - Test that burning 0 DSC reverts.
  - Test that burning DSC works as expected.
  - Test that burning more DSC than the user has reverts.
- Redeeming Collateral:
  - Test that redeeming collateral works as expected.
  - Test that redeeming more collateral than deposited reverts.
  - Test that redeeming collateral reverts if the health factor breaks.
- Combined Actions:
  - Test depositing collateral and minting DSC in one transaction.
  - Test redeeming collateral for DSC in one transaction.
- Liquidation:
  - Test that liquidating a user with a good health factor reverts.
  - Test a successful liquidation scenario.
