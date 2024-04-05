use aiken/list
use aiken/transaction.{ScriptContext}
use types.{CollaeralDatum}

type CollateralRedeemer {
  PayBackLoan
  LiquidateCollateral
}

type Redeemer {
  action: CollateralRedeemer,
}

validator {
  fn loan(
    datum: CollaeralDatum,
    redeemer: Redeemer,
    context: ScriptContext,
  ) -> Bool {
    when redeemer.action is {
      // todo
      PayBackLoan -> False
      // Check original lender is signing the transaction
      LiquidateCollateral -> {
        let must_be_signed_by_lender =
          list.has(
            context.transaction.extra_signatories,
            datum.lender_address_hash,
          )
        must_be_signed_by_lender
      }
    }
  }
}
