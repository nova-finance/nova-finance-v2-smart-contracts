use aiken/list
use aiken/transaction.{
  InlineDatum, Input, Output, OutputReference, ScriptContext, Spend,
  find_script_outputs,
}
use aiken/transaction/value.{quantity_of}
use types.{AddressHash, Info, LoanInput, LoanOfferDatum, LoanOutput}
use utils.{
  get_expected_collateral_from_inputs, get_output_collateral_info,
  get_own_validator_inputs, get_refund_info, info_matches,
}

type LoanRedeemer {
  GetLoan(AddressHash)
  CancelRequest
}

fn output_value_valid(
  outputs_to_script_validator: List<Output>,
  input_loan_info: List<Info>,
  outputs_collateral_info: List<Info>,
) -> Bool {
  let refund_to_validator_length: Int = list.length(outputs_to_script_validator)

  if refund_to_validator_length == 0 {
    let info_matches = info_matches(input_loan_info, outputs_collateral_info)
    info_matches
  } else if refund_to_validator_length == 1 {
    let outputs_refund_info: List<Info> =
      get_refund_info(outputs_to_script_validator)

    when list.at(outputs_refund_info, 0) is {
      Some(output_refund_info) ->
        when
          list.find(
            outputs_collateral_info,
            fn(output_collateral_info: Info) {
              output_collateral_info.lender_address_hash == output_refund_info.lender_address_hash
            },
          )
        is {
          Some(output_collateral_info) -> {
            let new_output_collateral_info =
              Info {
                loan_amount: output_refund_info.loan_amount + output_collateral_info.loan_amount,
                loan_asset: output_collateral_info.loan_asset,
                collateral_asset: output_collateral_info.collateral_asset,
                collateral_amount: output_refund_info.collateral_amount + output_collateral_info.collateral_amount,
                interest_asset: output_collateral_info.interest_asset,
                interest_amount: output_refund_info.interest_amount + output_collateral_info.interest_amount,
                lender_address_hash: output_collateral_info.lender_address_hash,
                loan_duration: output_collateral_info.loan_duration,
              }

            let filtered_output: List<Info> =
              list.filter(
                outputs_collateral_info,
                fn(output_collateral_info: Info) {
                  output_collateral_info.lender_address_hash == output_refund_info.lender_address_hash
                },
              )

            let combined_refund_and_collateral_info =
              list.push(filtered_output, new_output_collateral_info)

            let info_matches =
              info_matches(input_loan_info, combined_refund_and_collateral_info)
            info_matches
          }
          None -> False
        }

      None -> False
    }
  } else {
    False
  }
}

fn loan_is_valid(
  ctx: ScriptContext,
  collateral_script_hash: ByteArray,
  contract_stake_hash: ByteArray,
  output_ref: OutputReference,
  borrower_address_hash: AddressHash,
) -> Bool {
  let outputs_to_collateral_validator: List<Output> =
    find_script_outputs(ctx.transaction.outputs, collateral_script_hash)

  let outputs_to_script_validator: List<Output> =
    find_script_outputs(ctx.transaction.outputs, contract_stake_hash)

  let inputs_from_script_validator: List<Input> =
    get_own_validator_inputs(ctx, output_ref, contract_stake_hash)

  let total_loan_consumed: Int =
    list.foldl(
      inputs_from_script_validator,
      0,
      fn(input: Input, acc: Int) {
        expect InlineDatum(loan_datum) = input.output.datum
        expect loan_datum_typed: LoanOfferDatum = loan_datum
        let loan_amount: Int =
          quantity_of(
            input.output.value,
            loan_datum_typed.loan_asset.policy_id,
            loan_datum_typed.loan_asset.asset_name,
          )

        acc + loan_amount
      },
    )

  let loan_refunded: Int =
    list.foldl(
      outputs_to_script_validator,
      0,
      fn(output: Output, acc: Int) {
        expect InlineDatum(loan_datum) = output.datum
        expect loan_datum_typed: LoanOfferDatum = loan_datum
        let loan_amount: Int =
          quantity_of(
            output.value,
            loan_datum_typed.loan_asset.policy_id,
            loan_datum_typed.loan_asset.asset_name,
          )

        acc + loan_amount
      },
    )

  let total_loan_amount: Int = total_loan_consumed - loan_refunded

  let inputs_loan: List<LoanInput> =
    get_expected_collateral_from_inputs(inputs_from_script_validator)
  let input_loan_info: List<Info> =
    list.map(inputs_loan, fn(loan_input: LoanInput) { loan_input.info })

  let outputs_collateral: List<LoanOutput> =
    get_output_collateral_info(
      outputs_to_collateral_validator,
      total_loan_amount,
      borrower_address_hash,
      ctx,
    )

  let outputs_collateral_info: List<Info> =
    list.map(
      outputs_collateral,
      fn(loan_output: LoanOutput) { loan_output.info },
    )

  let output_value_valid =
    output_value_valid(
      outputs_to_script_validator,
      input_loan_info,
      outputs_collateral_info,
    )

  output_value_valid
}

validator(collateral_script_hash: ByteArray, contract_stake_hash: ByteArray) {
  fn loan(
    datum: LoanOfferDatum,
    redeemer: LoanRedeemer,
    ctx: ScriptContext,
  ) -> Bool {
    when redeemer is {
      // todo
      GetLoan(borrower_address_hash) ->
        when ctx.purpose is {
          Spend(output_ref) ->
            loan_is_valid(
              ctx,
              collateral_script_hash,
              contract_stake_hash,
              output_ref,
              borrower_address_hash,
            )

          _ -> False
        }

      CancelRequest -> {
        let must_be_signed_by_lender =
          list.has(ctx.transaction.extra_signatories, datum.lender_address_hash)
        must_be_signed_by_lender
      }
    }
  }
}
