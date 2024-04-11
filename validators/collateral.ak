use aiken/list
use aiken/transaction.{
  InlineDatum, Input, Output, OutputReference, ScriptContext, Spend,
  TransactionId, ValidityRange, find_script_outputs,
}
use aiken/transaction/value.{quantity_of}
use types.{
  AddressHash, AssetClass, CollateralDatum, InterestDatum, ValidateRepayInfo,
}
use utils.{get_own_validator_inputs}

type CollateralRedeemer {
  PayBackLoan(TransactionId)
  LiquidateCollateral
}

fn total_repay_amount(outputs_to_interest_validator: List<Output>) -> Int {
  list.foldl(
    outputs_to_interest_validator,
    0,
    fn(output: Output, acc: Int) {
      expect InlineDatum(interest_datum) = output.datum
      expect interest_datum_typed: InterestDatum = interest_datum
      let repaid_amount: Int =
        quantity_of(
          output.value,
          interest_datum_typed.repay_asset.policy_id,
          interest_datum_typed.repay_asset.asset_name,
        )

      acc + repaid_amount
    },
  )
}

// map filter, make sure the same tx id, deadline has not passed, and each total_loan_amount = get_total_repaid_amount.
// signed by borrower
fn get_inputs_collateral_info(
  inputs_from_script_validator: List<Input>,
  total_repaid_amount: Int,
  tx_id: TransactionId,
  validity_range: ValidityRange,
  signatures: List<AddressHash>,
) -> List<ValidateRepayInfo> {
  list.filter_map(
    inputs_from_script_validator,
    fn(input_from_script_validator: Input) {
      expect InlineDatum(collateral_datum) =
        input_from_script_validator.output.datum
      expect collateral_datum_typed: CollateralDatum = collateral_datum

      let tx_id_valid = tx_id == collateral_datum_typed.tx_id
      let total_loan_amount_valid =
        total_repaid_amount == collateral_datum_typed.total_repay_amount
      let deadline_not_passed =
        collateral_datum_typed.lend_time + collateral_datum_typed.loan_duration > utils.get_lower_bound(
          validity_range,
        )
      let signed_by_borrower =
        list.has(signatures, collateral_datum_typed.borrower_address_hash)

      let collateral_valid =
        tx_id_valid && total_loan_amount_valid && deadline_not_passed && signed_by_borrower

      if collateral_valid {
        None
      } else {
        Some(
          ValidateRepayInfo {
            repay_amount: collateral_datum_typed.total_repay_amount,
            repay_asset: collateral_datum_typed.loan_asset,
            lender_address_hash: collateral_datum_typed.lender_address_hash,
          },
        )
      }
    },
  )
}

fn get_outputs_interest_info(
  outputs_to_interest_validator: List<Output>,
) -> List<ValidateRepayInfo> {
  list.map(
    outputs_to_interest_validator,
    fn(output: Output) {
      expect InlineDatum(interest_datum) = output.datum
      expect interest_datum_typed: InterestDatum = interest_datum

      ValidateRepayInfo {
        repay_amount: quantity_of(
          output.value,
          interest_datum_typed.repay_asset.policy_id,
          interest_datum_typed.repay_asset.asset_name,
        ),
        repay_asset: interest_datum_typed.repay_asset,
        lender_address_hash: interest_datum_typed.lender_address_hash,
      }
    },
  )
}

fn interest_payment_is_valid(
  ctx: ScriptContext,
  interest_script_hash: ByteArray,
  contract_stake_hash: ByteArray,
  output_ref: OutputReference,
  tx_id: TransactionId,
) -> Bool {
  // same tx id, total value = value in datum, deadline has not passed 
  let validity_range: ValidityRange = ctx.transaction.validity_range

  let signatures: List<AddressHash> = ctx.transaction.extra_signatories

  let outputs_to_interest_validator: List<Output> =
    find_script_outputs(ctx.transaction.outputs, interest_script_hash)

  let inputs_from_script_validator: List<Input> =
    get_own_validator_inputs(ctx, output_ref, contract_stake_hash)

  let total_repay_amount: Int =
    total_repay_amount(outputs_to_interest_validator)

  let inputs_collateral_info: List<ValidateRepayInfo> =
    get_inputs_collateral_info(
      inputs_from_script_validator,
      total_repay_amount,
      tx_id,
      validity_range,
      signatures,
    )

  let outputs_interest_info: List<ValidateRepayInfo> =
    get_outputs_interest_info(outputs_to_interest_validator)

  let info_difference =
    list.difference(inputs_collateral_info, outputs_interest_info)

  let info_matches = list.length(info_difference) == 0
  info_matches
}

validator(interest_script_hash: ByteArray, contract_stake_hash: ByteArray) {
  fn loan(
    datum: CollateralDatum,
    redeemer: CollateralRedeemer,
    ctx: ScriptContext,
  ) -> Bool {
    when redeemer is {
      // todo 
      PayBackLoan(tx_id) ->
        when ctx.purpose is {
          Spend(output_ref) ->
            interest_payment_is_valid(
              ctx,
              interest_script_hash,
              contract_stake_hash,
              output_ref,
              tx_id,
            )

          _ -> False
        }

      LiquidateCollateral -> {
        let must_be_signed_by_lender =
          list.has(ctx.transaction.extra_signatories, datum.lender_address_hash)
        let deadline_passed =
          datum.loan_duration + datum.lend_time < utils.get_lower_bound(
            ctx.transaction.validity_range,
          )
        must_be_signed_by_lender && deadline_passed
      }
    }
  }
}
