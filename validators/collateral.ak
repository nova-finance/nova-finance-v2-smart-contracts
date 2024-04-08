use aiken/list
use aiken/transaction.{ScriptContext}
use types.{CollateralDatum}
use utils

type CollateralRedeemer {
  PayBackLoan
  LiquidateCollateral
}

validator {
  fn loan(
    datum: CollateralDatum,
    redeemer: CollateralRedeemer,
    context: ScriptContext,
  ) -> Bool {
    when redeemer is {
      // todo
      PayBackLoan -> False
      // Check original lender is signing the transaction 
      LiquidateCollateral -> {
        let must_be_signed_by_lender =
          list.has(
            context.transaction.extra_signatories,
            datum.lender_address_hash,
          )
        let deadline_passed =
          datum.loan_duration + datum.lend_time < utils.get_lower_bound(
            context.transaction.validity_range,
          )
        must_be_signed_by_lender && deadline_passed
      }
    }
  }
}
