use aiken/list
use aiken/transaction.{
  InlineDatum, Input, Output, ScriptContext, ValidityRange, WithdrawFrom,
  find_script_outputs,
}
use aiken/transaction/value.{quantity_of}
use types.{
  AddressHash, AssetClass, CollateralDatum, InterestDatum, LoanAndInterestAmount,
  ValidateRepayInfo,
}
use utils.{get_inputs_from_script}

fn get_loan_and_interest_from_output(output: Output) -> LoanAndInterestAmount {
  expect InlineDatum(interest_datum) = output.datum
  expect interest_datum_typed: InterestDatum = interest_datum
  let loan_and_interest_asset_same =
    interest_datum_typed.repay_loan_asset == interest_datum_typed.repay_interest_asset

  when loan_and_interest_asset_same is {
    True -> {
      let total_asset_amount =
        quantity_of(
          output.value,
          interest_datum_typed.repay_loan_asset.policy_id,
          interest_datum_typed.repay_loan_asset.asset_name,
        )

      LoanAndInterestAmount {
        loan_amount: total_asset_amount - interest_datum_typed.repay_interest_amount,
        interest_amount: total_asset_amount - interest_datum_typed.repay_loan_amount,
      }
    }
    False ->
      LoanAndInterestAmount {
        loan_amount: quantity_of(
          output.value,
          interest_datum_typed.repay_loan_asset.policy_id,
          interest_datum_typed.repay_loan_asset.asset_name,
        ),
        interest_amount: quantity_of(
          output.value,
          interest_datum_typed.repay_interest_asset.policy_id,
          interest_datum_typed.repay_interest_asset.asset_name,
        ),
      }
  }
}

fn get_total_repay_loan_and_interest_amount(
  outputs_to_interest_validator: List<Output>,
) -> LoanAndInterestAmount {
  list.foldl(
    outputs_to_interest_validator,
    LoanAndInterestAmount { loan_amount: 0, interest_amount: 0 },
    fn(output: Output, acc: LoanAndInterestAmount) {
      let loan_and_interest_amount = get_loan_and_interest_from_output(output)

      LoanAndInterestAmount {
        loan_amount: acc.loan_amount + loan_and_interest_amount.loan_amount,
        interest_amount: acc.interest_amount + loan_and_interest_amount.interest_amount,
      }
    },
  )
}

fn get_inputs_collateral_info(
  inputs_from_collateral_validator: List<Input>,
  total_repaid_amount: LoanAndInterestAmount,
  validity_range: ValidityRange,
  signatures: List<AddressHash>,
) -> List<ValidateRepayInfo> {
  list.filter_map(
    inputs_from_collateral_validator,
    fn(input_from_collateral_validator: Input) {
      expect InlineDatum(collateral_datum) =
        input_from_collateral_validator.output.datum
      expect collateral_datum_typed: CollateralDatum = collateral_datum

      let total_loan_amount_valid =
        total_repaid_amount.loan_amount == collateral_datum_typed.total_loan_amount
      let total_interest_amount_valid =
        total_repaid_amount.interest_amount == collateral_datum_typed.total_interest_amount
      let deadline_not_passed =
        collateral_datum_typed.lend_time + collateral_datum_typed.loan_duration > utils.get_lower_bound(
          validity_range,
        )
      let signed_by_borrower =
        list.has(signatures, collateral_datum_typed.borrower_address_hash)

      let collateral_valid =
        total_loan_amount_valid && deadline_not_passed && signed_by_borrower && total_interest_amount_valid

      if collateral_valid {
        None
      } else {
        Some(
          ValidateRepayInfo {
            repay_loan_amount: collateral_datum_typed.total_loan_amount,
            repay_loan_asset: collateral_datum_typed.loan_asset,
            repay_interest_amount: collateral_datum_typed.total_interest_amount,
            repay_interest_asset: collateral_datum_typed.interest_asset,
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

      let loan_and_interest_amount: LoanAndInterestAmount =
        get_loan_and_interest_from_output(output)

      ValidateRepayInfo {
        repay_loan_amount: loan_and_interest_amount.loan_amount,
        repay_loan_asset: interest_datum_typed.repay_loan_asset,
        repay_interest_amount: loan_and_interest_amount.interest_amount,
        repay_interest_asset: interest_datum_typed.repay_interest_asset,
        lender_address_hash: interest_datum_typed.lender_address_hash,
      }
    },
  )
}

fn interest_payment_is_valid(
  ctx: ScriptContext,
  interest_script_hash: ByteArray,
  collateral_stake_hash: ByteArray,
) -> Bool {
  let validity_range: ValidityRange = ctx.transaction.validity_range

  let signatures: List<AddressHash> = ctx.transaction.extra_signatories

  let outputs_to_interest_validator: List<Output> =
    find_script_outputs(ctx.transaction.outputs, interest_script_hash)

  let inputs_from_collateral_validator: List<Input> =
    get_inputs_from_script(ctx.transaction.inputs, collateral_stake_hash)

  let total_repay_amount: LoanAndInterestAmount =
    get_total_repay_loan_and_interest_amount(outputs_to_interest_validator)

  let inputs_collateral_info: List<ValidateRepayInfo> =
    get_inputs_collateral_info(
      inputs_from_collateral_validator,
      total_repay_amount,
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

validator(interest_script_hash: ByteArray, collateral_stake_hash: ByteArray) {
  fn loan(_datum: Int, _redeemer: Int, ctx: ScriptContext) -> Bool {
    when ctx.purpose is {
      WithdrawFrom(_) ->
        interest_payment_is_valid(
          ctx,
          interest_script_hash,
          collateral_stake_hash,
        )

      _ -> False
    }
  }
}
