use aiken/list
use aiken/transaction.{
  InlineDatum, Input, Output, OutputReference, ScriptContext, Spend,
  find_script_outputs,
}
use aiken/transaction/value.{quantity_of}
use types.{
  AddressHash, CollateralDatum, Info, LoanInput, LoanOfferDatum, LoanOutput,
}
use utils.{
  get_expected_collateral_from_inputs, get_output_collateral_info,
  get_own_validator_inputs, get_refund_info,
}

type LoanRedeemer {
  GetLoan(AddressHash)
  CancelRequest
}

fn collateral_output_is_valid(
  outputs_to_collateral_validator: List<Output>,
  outputs_to_script_validator: List<Output>,
  inputs_from_script_validator: List<Input>,
) -> Bool {
  let refund_output_length: Int = list.length(outputs_to_script_validator)

  let inputs_loan: List<LoanInput> =
    get_expected_collateral_from_inputs(inputs_from_script_validator)

  let input_loan_info: List<Info> =
    list.map(inputs_loan, fn(loan_input: LoanInput) { loan_input.info })

  let outputs_collateral: List<LoanOutput> =
    get_output_collateral_info(outputs_to_collateral_validator)

  let outputs_collateral_info: List<Info> =
    list.map(
      outputs_collateral,
      fn(loan_output: LoanOutput) { loan_output.info },
    )

  if refund_output_length == 0 {
    let info_difference =
      list.difference(input_loan_info, outputs_collateral_info)

    let info_matches = list.length(info_difference) == 0
    info_matches
  } else if refund_output_length == 1 {
    let outputs_refund: List<LoanOutput> =
      get_refund_info(outputs_to_script_validator)

    when list.at(outputs_refund, 0) is {
      Some(refund_output) ->
        when
          list.find(
            outputs_collateral_info,
            fn(output_collateral_info: Info) {
              output_collateral_info.lender_address_hash == refund_output.info.lender_address_hash
            },
          )
        is {
          Some(collateral_refund_utxo) -> {
            let new_output_collateral_amount: Int =
              refund_output.info.collateral_amount + collateral_refund_utxo.collateral_amount

            let new_output_collateral_info =
              Info {
                collateral_amount: new_output_collateral_amount,
                loan_duration: collateral_refund_utxo.loan_duration,
                interest_asset: collateral_refund_utxo.interest_asset,
                interest_amount: collateral_refund_utxo.interest_amount,
                lender_address_hash: collateral_refund_utxo.lender_address_hash,
              }

            let filtered_output: List<Info> =
              list.filter(
                outputs_collateral_info,
                fn(output_collateral_info: Info) {
                  output_collateral_info.lender_address_hash == refund_output.info.lender_address_hash
                },
              )

            let combined_refund_and_collateral_info =
              list.push(filtered_output, new_output_collateral_info)

            let info_difference =
              list.difference(
                input_loan_info,
                combined_refund_and_collateral_info,
              )
            let info_matches = list.length(info_difference) == 0
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

  let collateral_output_datum_valid =
    list.all(
      outputs_to_collateral_validator,
      fn(output: Output) {
        expect InlineDatum(collateral_datum) = output.datum
        expect collateral_datum_typed: CollateralDatum = collateral_datum

        let borrower_address_valid =
          collateral_datum_typed.borrower_address_hash == borrower_address_hash
        let tx_id_valid = collateral_datum_typed.tx_id == ctx.transaction.id
        let lend_time_valid =
          collateral_datum_typed.lend_time == utils.get_lower_bound(
            ctx.transaction.validity_range,
          )
        let total_loan_amount_valid =
          collateral_datum_typed.total_loan_amount == total_loan_amount

        borrower_address_valid && tx_id_valid && lend_time_valid && total_loan_amount_valid
      },
    )

  let collateral_output_value_valid =
    collateral_output_is_valid(
      outputs_to_collateral_validator,
      outputs_to_script_validator,
      inputs_from_script_validator,
    )

  collateral_output_datum_valid && collateral_output_value_valid
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
