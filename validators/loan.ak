use aiken/list
use aiken/transaction.{
  InlineDatum, Input, Output, OutputReference, ScriptContext, Spend,
  find_script_outputs,
}
use aiken/transaction/value.{Value, quantity_of}
use types.{AddressHash, CollateralDatum, Info, LoanOfferDatum}
use utils.{get_lower_bound, get_own_validator_inputs, info_matches}

type LoanRedeemer {
  GetLoan(AddressHash)
  CancelRequest
}

fn get_info_from_loan_offer(
  loan_offer_datum: LoanOfferDatum,
  value: Value,
) -> Info {
  Info {
    loan_amount: quantity_of(
      value,
      loan_offer_datum.loan_asset.policy_id,
      loan_offer_datum.loan_asset.asset_name,
    ),
    loan_asset: loan_offer_datum.loan_asset,
    collateral_amount: loan_offer_datum.collateral_amount,
    collateral_asset: loan_offer_datum.collateral_asset,
    interest_amount: loan_offer_datum.interest_amount,
    interest_asset: loan_offer_datum.interest_asset,
    lender_address_hash: loan_offer_datum.lender_address_hash,
    loan_duration: loan_offer_datum.loan_duration,
  }
}

fn get_total_loan_amount(
  list: List<Input>,
  inputs_from_script_validator: List<Input>,
  outputs_to_script_validator: List<Output>,
) -> Int {
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
}

fn get_outputs_refund_info(script_outputs: List<Output>) -> List<Info> {
  list.map(
    script_outputs,
    fn(output: Output) {
      expect InlineDatum(loan_offer_datum) = output.datum
      expect loan_offer_datum_typed: LoanOfferDatum = loan_offer_datum
      let info = get_info_from_loan_offer(loan_offer_datum_typed, output.value)
      info
    },
  )
}

fn get_inputs_loan_info(inputs_from_script: List<Input>) -> List<Info> {
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
          fn(input_loan: Info) {
            input_loan.lender_address_hash == loan_offer_datum_typed.lender_address_hash
          },
        )
      is {
        Some(duplicate_loan) -> {
          let new_input_loan_info =
            Info {
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
              fn(input_loan: Info) {
                input_loan.lender_address_hash != loan_offer_datum_typed.lender_address_hash
              },
            )

          [new_input_loan_info, ..removed_duplicate_collateral_list]
        }
        None -> {
          let input_loan_info =
            get_info_from_loan_offer(loan_offer_datum_typed, output.value)

          [input_loan_info, ..inputs_loan]
        }
      }
    },
  )
}

fn get_outputs_collateral_info(
  script_outputs: List<Output>,
  outputs_to_script_validator: List<Output>,
  total_loan_amount: Int,
  borrower_address_hash: AddressHash,
  ctx: ScriptContext,
) -> List<Info> {
  let outputs_collateral_info =
    list.filter_map(
      script_outputs,
      fn(output: Output) {
        expect InlineDatum(collateral_datum) = output.datum
        expect collateral_datum_typed: CollateralDatum = collateral_datum

        let borrower_address_valid =
          collateral_datum_typed.borrower_address_hash == borrower_address_hash
        let tx_id_valid = collateral_datum_typed.tx_id == ctx.transaction.id
        let lend_time_valid =
          collateral_datum_typed.lend_time == get_lower_bound(
            ctx.transaction.validity_range,
          )
        let total_loan_amount_valid =
          collateral_datum_typed.total_loan_amount == total_loan_amount

        let output_datum_valid =
          borrower_address_valid && tx_id_valid && lend_time_valid && total_loan_amount_valid

        if output_datum_valid {
          let output_collateral_info =
            Info {
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
  let refund_to_validator_length: Int = list.length(outputs_to_script_validator)

  if refund_to_validator_length == 0 {
    outputs_collateral_info
  } else if refund_to_validator_length == 1 {
    let outputs_refund_info: List<Info> =
      get_outputs_refund_info(outputs_to_script_validator)

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

            combined_refund_and_collateral_info
          }
          None -> fail
        }

      None -> fail
    }
  } else {
    fail
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

  let total_loan_amount: Int =
    get_total_loan_amount(
      ctx.transaction.inputs,
      inputs_from_script_validator,
      outputs_to_script_validator,
    )

  let outputs_collateral_info: List<Info> =
    get_outputs_collateral_info(
      outputs_to_collateral_validator,
      outputs_to_script_validator,
      total_loan_amount,
      borrower_address_hash,
      ctx,
    )

  let inputs_loan_info: List<Info> =
    get_inputs_loan_info(inputs_from_script_validator)

  let info_matches = info_matches(inputs_loan_info, outputs_collateral_info)
  info_matches
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
