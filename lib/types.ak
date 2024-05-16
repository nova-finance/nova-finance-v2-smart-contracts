use aiken/hash.{Blake2b_224, Hash}
use aiken/transaction/credential.{Script, VerificationKey}
use aiken/transaction/value.{AssetName, PolicyId, Value}

pub type POSIXTime =
  Int

pub type AssetClass {
  policy_id: PolicyId,
  asset_name: AssetName,
}

pub type AddressHash =
  Hash<Blake2b_224, VerificationKey>

pub type OfferLoanDatum {
  loan_amount: Int,
  loan_asset: AssetClass,
  collateral_amount: Int,
  collateral_asset: AssetClass,
  interest_amount: Int,
  interest_asset: AssetClass,
  loan_duration: POSIXTime,
  lender_address_hash: AddressHash,
  liquidation_policy: PolicyId,
  collateral_factor: Int,
}

pub type CollateralDatum {
  loan_amount: Int,
  loan_asset: AssetClass,
  collateral_asset: AssetClass,
  interest_amount: Int,
  interest_asset: AssetClass,
  loan_duration: POSIXTime,
  lend_time: POSIXTime,
  lender_address_hash: AddressHash,
  total_interest_amount: Int,
  total_loan_amount: Int,
  borrower_address_hash: AddressHash,
  liquidation_policy: PolicyId,
  collateral_factor: Int,
}

pub type InterestDatum {
  repay_loan_amount: Int,
  repay_loan_asset: AssetClass,
  repay_interest_amount: Int,
  repay_interest_asset: AssetClass,
  lender_address_hash: AddressHash,
}

pub type AddressAndValue {
  address_hash: AddressHash,
  value: Value,
}

pub type ValidateLoanInfo {
  loan_amount: Int,
  loan_asset: AssetClass,
  collateral_amount: Int,
  collateral_asset: AssetClass,
  interest_amount: Int,
  interest_asset: AssetClass,
  lender_address_hash: AddressHash,
  loan_duration: POSIXTime,
  lovelace_amount: Int,
  liquidation_policy: PolicyId,
  collateral_factor: Int,
}

pub type ValidateRepayInfo {
  repay_loan_amount: Int,
  repay_loan_asset: AssetClass,
  repay_interest_amount: Int,
  repay_interest_asset: AssetClass,
  lender_address_hash: AddressHash,
}

pub type ValidatorHash =
  Hash<Blake2b_224, Script>

pub type LoanAndInterestAmount {
  loan_amount: Int,
  interest_amount: Int,
}
