use aiken/list
use aiken/transaction.{
  InlineDatum, Input, Output, ScriptContext, WithdrawFrom, find_script_outputs,
}
use aiken/transaction/value.{quantity_of}
use types.{
  CollateralDatum, LoanAndInterestAmount, LoanOfferDatum, ValidateLoanInfo,
}
use utils.{get_inputs_from_script, get_lower_bound}

fn get_total_repay_amount(
  list: List<Input>,
  inputs_from_script_validator: List<Input>,
) -> LoanAndInterestAmount {
  list.foldl(
    inputs_from_script_validator,
    LoanAndInterestAmount { loan_amount: 0, interest_amount: 0 },
    fn(input: Input, acc: LoanAndInterestAmount) {
      expect InlineDatum(loan_datum) = input.output.datum
      expect loan_datum_typed: LoanOfferDatum = loan_datum
      let interest_amount: Int = loan_datum_typed.interest_amount
      let loan_amount: Int =
        quantity_of(
          input.output.value,
          loan_datum_typed.loan_asset.policy_id,
          loan_datum_typed.loan_asset.asset_name,
        )

      LoanAndInterestAmount {
        loan_amount: acc.loan_amount + loan_amount,
        interest_amount: acc.interest_amount + interest_amount,
      }
    },
  )
}

fn get_inputs_loan_info(
  inputs_from_script: List<Input>,
) -> List<ValidateLoanInfo> {
  list.foldl(
    inputs_from_script,
    [],
    fn(input, inputs_loan) {
      let output: Output = input.output
      expect InlineDatum(loan_offer_datum) = output.datum
      expect loan_offer_datum_typed: LoanOfferDatum = loan_offer_datum

      when
        list.find(
          inputs_loan,
          fn(input_loan: ValidateLoanInfo) {
            input_loan.lender_address_hash == loan_offer_datum_typed.lender_address_hash && input_loan.loan_asset == loan_offer_datum_typed.loan_asset && input_loan.collateral_asset == loan_offer_datum_typed.collateral_asset && input_loan.interest_asset == loan_offer_datum_typed.interest_asset && input_loan.loan_duration == loan_offer_datum_typed.loan_duration
          },
        )
      is {
        Some(duplicate_loan) -> {
          let new_input_loan_info =
            ValidateLoanInfo {
              loan_amount: duplicate_loan.loan_amount + quantity_of(
                output.value,
                loan_offer_datum_typed.loan_asset.policy_id,
                loan_offer_datum_typed.loan_asset.asset_name,
              ),
              loan_asset: loan_offer_datum_typed.loan_asset,
              collateral_amount: loan_offer_datum_typed.collateral_amount + duplicate_loan.collateral_amount,
              collateral_asset: loan_offer_datum_typed.collateral_asset,
              interest_amount: loan_offer_datum_typed.interest_amount + duplicate_loan.interest_amount,
              interest_asset: loan_offer_datum_typed.interest_asset,
              lender_address_hash: loan_offer_datum_typed.lender_address_hash,
              loan_duration: loan_offer_datum_typed.loan_duration,
            }

          let removed_duplicate_collateral_list =
            list.filter(
              inputs_loan,
              fn(input_loan: ValidateLoanInfo) {
                input_loan.lender_address_hash != loan_offer_datum_typed.lender_address_hash
              },
            )

          [new_input_loan_info, ..removed_duplicate_collateral_list]
        }

        None -> {
          let input_loan_info =
            ValidateLoanInfo {
              loan_amount: quantity_of(
                output.value,
                loan_offer_datum_typed.loan_asset.policy_id,
                loan_offer_datum_typed.loan_asset.asset_name,
              ),
              loan_asset: loan_offer_datum_typed.loan_asset,
              collateral_amount: loan_offer_datum_typed.collateral_amount,
              collateral_asset: loan_offer_datum_typed.collateral_asset,
              interest_amount: loan_offer_datum_typed.interest_amount,
              interest_asset: loan_offer_datum_typed.interest_asset,
              lender_address_hash: loan_offer_datum_typed.lender_address_hash,
              loan_duration: loan_offer_datum_typed.loan_duration,
            }

          [input_loan_info, ..inputs_loan]
        }
      }
    },
  )
}

fn get_outputs_collateral_info(
  script_outputs: List<Output>,
  total_repay_amount: LoanAndInterestAmount,
  ctx: ScriptContext,
) -> List<ValidateLoanInfo> {
  list.filter_map(
    script_outputs,
    fn(output: Output) {
      expect InlineDatum(collateral_datum) = output.datum
      expect collateral_datum_typed: CollateralDatum = collateral_datum

      let tx_id_valid = collateral_datum_typed.tx_id == ctx.transaction.id
      let lend_time_valid =
        collateral_datum_typed.lend_time == get_lower_bound(
          ctx.transaction.validity_range,
        )
      let total_loan_amount_valid =
        collateral_datum_typed.total_loan_amount == total_repay_amount.loan_amount
      let total_interest_amount_valid =
        collateral_datum_typed.total_interest_amount == total_repay_amount.interest_amount

      let output_datum_valid =
        tx_id_valid && lend_time_valid && total_loan_amount_valid && total_interest_amount_valid

      if output_datum_valid {
        let output_collateral_info =
          ValidateLoanInfo {
            loan_amount: collateral_datum_typed.loan_amount,
            loan_asset: collateral_datum_typed.loan_asset,
            collateral_amount: quantity_of(
              output.value,
              collateral_datum_typed.collateral_asset.policy_id,
              collateral_datum_typed.collateral_asset.asset_name,
            ),
            collateral_asset: collateral_datum_typed.collateral_asset,
            interest_amount: collateral_datum_typed.interest_amount,
            interest_asset: collateral_datum_typed.interest_asset,
            lender_address_hash: collateral_datum_typed.lender_address_hash,
            loan_duration: collateral_datum_typed.loan_duration,
          }

        Some(output_collateral_info)
      } else {
        None
      }
    },
  )
}

fn loan_is_valid(
  ctx: ScriptContext,
  collateral_script_hash: ByteArray,
  loan_script_hash: ByteArray,
) -> Bool {
  let outputs_to_collateral_validator: List<Output> =
    find_script_outputs(ctx.transaction.outputs, collateral_script_hash)

  let inputs_from_script_validator: List<Input> =
    get_inputs_from_script(ctx.transaction.inputs, loan_script_hash)

  let total_repay_amount: LoanAndInterestAmount =
    get_total_repay_amount(ctx.transaction.inputs, inputs_from_script_validator)

  let outputs_collateral_info: List<ValidateLoanInfo> =
    get_outputs_collateral_info(
      outputs_to_collateral_validator,
      total_repay_amount,
      ctx,
    )

  let inputs_loan_info: List<ValidateLoanInfo> =
    get_inputs_loan_info(inputs_from_script_validator)

  let info_difference =
    list.difference(inputs_loan_info, outputs_collateral_info)

  let info_matches = list.length(info_difference) == 0
  info_matches
}

validator(collateral_script_hash: ByteArray, loan_script_hash: ByteArray) {
  fn loan(_datum: Int, _redeemer: Int, ctx: ScriptContext) -> Bool {
    when ctx.purpose is {
      WithdrawFrom(_) ->
        loan_is_valid(ctx, collateral_script_hash, loan_script_hash)

      _ -> False
    }
  }
}
