use aiken/interval.{Finite}
use aiken/list
use aiken/option
use aiken/transaction.{
  InlineDatum, Input, Output, OutputReference, ScriptContext, ValidityRange,
}
use aiken/transaction/credential.{
  Address, Inline, ScriptCredential, VerificationKeyCredential,
}
use aiken/transaction/value.{quantity_of}
use types.{
  AddressHash, AssetClass, CollateralDatum, ExpectedCollateral, LoanOfferDatum,
  POSIXTime, ValidatorHash,
}

pub fn scripthash_address(scripthash: ByteArray, stake_hash: ByteArray) {
  Address {
    payment_credential: ScriptCredential(scripthash),
    stake_credential: Some(Inline(VerificationKeyCredential(stake_hash))),
  }
}

pub fn get_lower_bound(range: ValidityRange) -> Int {
  expect Finite(lower_bound) = range.lower_bound.bound_type
  lower_bound
}

pub fn get_output_collateral_info(
  script_outputs: List<Output>,
) -> List<ExpectedCollateral> {
  list.map(
    script_outputs,
    fn(output) {
      expect InlineDatum(collateral_datum) = output.datum
      expect collateral_datum_typed: CollateralDatum = collateral_datum

      let collateral_amount: Int =
        quantity_of(
          output.value,
          collateral_datum_typed.collateral_asset.policy_id,
          collateral_datum_typed.collateral_asset.asset_name,
        )
      let loan_duration: POSIXTime = collateral_datum_typed.loan_duration
      let interest_asset: AssetClass = collateral_datum_typed.interest_asset
      let interest_amount: Int = collateral_datum_typed.interest_amount
      let lender_address_hash: AddressHash =
        collateral_datum_typed.lender_address_hash

      let output_collateral =
        ExpectedCollateral {
          collateral_amount,
          loan_duration,
          interest_asset,
          interest_amount,
          lender_address_hash,
        }
      output_collateral
    },
  )
}

pub fn own_validator_script_address_hash(
  inputs: List<Input>,
  output_reference: OutputReference,
) -> Option<ValidatorHash> {
  inputs
    |> list.find(fn(input) { input.output_reference == output_reference })
    |> option.map(fn(v) { v.output })
    |> option.map(fn(v) { v.address })
    |> option.map(fn(v) { v.payment_credential })
    |> option.map(
        fn(v) {
          when v is {
            ScriptCredential(hash) -> Some(hash)
            _ -> None
          }
        },
      )
    |> option.flatten()
}

pub fn get_own_validator_address(
  ctx: ScriptContext,
  output_reference: OutputReference,
  stake_hash,
) -> Address {
  expect Some(validator_hash) =
    own_validator_script_address_hash(ctx.transaction.inputs, output_reference)
  scripthash_address(validator_hash, stake_hash)
}

pub fn get_own_validator_inputs(
  ctx: ScriptContext,
  output_reference: OutputReference,
  stake_hash: ByteArray,
) -> List<Input> {
  let script_own_address =
    get_own_validator_address(ctx, output_reference, stake_hash)

  // Get all inputs from the transaction
  list.filter(
    ctx.transaction.inputs,
    fn(input) { input.output.address == script_own_address },
  )
}

pub fn get_expected_collateral_from_inputs(
  inputs_from_script: List<Input>,
) -> List<ExpectedCollateral> {
  list.foldl(
    inputs_from_script,
    [],
    fn(input, expected_collateral_from_inputs) {
      let output: Output = input.output
      expect InlineDatum(loan_offer_datum) = output.datum
      expect loan_offer_datum_typed: LoanOfferDatum = loan_offer_datum

      let lender_address_hash: AddressHash =
        loan_offer_datum_typed.lender_address_hash

      let collateral_amount: Int =
        quantity_of(
          output.value,
          loan_offer_datum_typed.collateral_asset.policy_id,
          loan_offer_datum_typed.collateral_asset.asset_name,
        )

      let loan_duration: POSIXTime = loan_offer_datum_typed.loan_duration
      let interest_asset: AssetClass = loan_offer_datum_typed.interest_asset
      let interest_amount: Int = loan_offer_datum_typed.interest_amount

      when
        list.find(
          expected_collateral_from_inputs,
          fn(expected_collateral: ExpectedCollateral) {
            expected_collateral.lender_address_hash == lender_address_hash
          },
        )
      is {
        Some(duplicate_collateral) -> {
          let new_collateral =
            ExpectedCollateral {
              collateral_amount: duplicate_collateral.collateral_amount + collateral_amount,
              loan_duration: duplicate_collateral.loan_duration,
              interest_asset: duplicate_collateral.interest_asset,
              interest_amount: duplicate_collateral.interest_amount,
              lender_address_hash: duplicate_collateral.lender_address_hash,
            }

          let removed_duplicate_collateral_list =
            list.filter(
              expected_collateral_from_inputs,
              fn(expected_collateral) {
                expected_collateral.lender_address_hash != lender_address_hash
              },
            )

          [new_collateral, ..removed_duplicate_collateral_list]
        }
        None -> {
          let expected_collateral =
            ExpectedCollateral {
              collateral_amount,
              loan_duration,
              interest_asset,
              interest_amount,
              lender_address_hash,
            }
          [expected_collateral, ..expected_collateral_from_inputs]
        }
      }
    },
  )
}
