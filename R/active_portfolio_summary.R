
#' Active Porfolio Return Summary
#'
#' Estimates active portfolio return measures.
#' @param capital Initial capital.
#' @param currency Currency.
#' @param w_port Portfolio weights.
#' @param w_bench Benchmark weights.
#' @param asset_data Assets DF.
#' @param series_list Series list.
#' @param per Period.
#' @param rebal_per Rebalancing per. in months.
#' @param slippage Slippage.
#' @param commission Commission.
#' @param port_name Portfolio name.
#' @param invest_assets Invest assets.
#' @param fixed_tickers Fixed tickers list (dates and tickers per asset).
#' @param weights_tac Tactical weights xts.
#' @param sync_dates Bool, sync. dates.
#' @param fund_complete Bool, indicates if benchmark funds are used.
#' @param header_df DF headers.
#' @return Active summary data frame.
#' @export

active_portfolio_summary <- function(capital, currency, w_port, w_bench, ref_dates, asset_data, series_list, per = "monthly", rebal_per = 1, slippage = 0, commission = 0, port_name = NULL, invest_assets = NULL, fixed_tickers = NULL, weights_tac = NULL, sync_dates = NULL, total_ret = FALSE, fund_complete = FALSE, header_df = c("Ret Total Bench", "Ret Total Port", "Ret Prom Bench", "Ret Prom Port", "Vol", "Sharpe", "Alpha", "TE", "RI", "AA", "SS/INTER")) {

  freq <- switch(per, 'daily' = 252, 'monthly' = 12, 'quarterly' = 4)
  if(is.null(w_port) & is.null(w_bench)){ stop("Null portafolios. Check weights!")}

  if(is.null(w_port)){
    w_port <- w_bench
  }

  asset_names <- unique(names(c(w_port, w_bench)))

  bench_curr <- unique(asset_data$Currency[match(asset_names, asset_data$Asset)])
  port_curr <- bench_curr
  if(!is.null(invest_assets) && invest_assets == 'ETF'){
    port_curr <- asset_data$CurrencyETF[match(asset_names, asset_data$Asset)]
  }else if (!is.null(invest_assets) && invest_assets == 'IA'){
    port_curr <- asset_data$CurrencyIA[match(asset_names, asset_data$Asset)]
    if(!is.null(fixed_tickers)){
      port_curr[match(names(fixed_tickers), asset_names)] <- asset_data$Currency[match(sapply(names(fixed_tickers), function(x) get_asset(tail(fixed_tickers[[x]]$tk), asset_data)), asset_data$Asset)]
    }
  }
  port_curr <- unique(port_curr)
  asset_names_diff <- setdiff(asset_names, names(fixed_tickers))
  series_back <- series_merge(series_list, ref_dates, asset_data, currency, asset_names_diff, port_curr, convert_to_ref = FALSE, invest_assets = invest_assets, fixed_tickers =  NULL)

  if(!is.null(fixed_tickers)){
    series_comp <- series_compose(series_list, asset_data, fixed_tickers, ref_dates, ref_curr=NULL, join = 'inner')
    series_back <- merge.xts(series_back, series_comp$series, join = "inner")
    colnames(series_back) <- c(asset_names_diff, port_curr, names(fixed_tickers))
    series_back <- series_back[, c(asset_names, port_curr)]
    fixed_curr <- series_comp$currs
  }

  # the date 01012000 is added when completing with benchmark
  series_bench <- series_merge(series_list, c(index(series_back)[1], tail(index(series_back), 1)), asset_data, currency, asset_names, bench_curr, convert_to_ref = FALSE)
  if(fund_complete && !is.null(weights_tac) && !is.null(invest_assets) && index(weights_tac)[1]==dmy("01012000")){
    series_back_list <- list(series_bench, series_back)
    names(series_back_list) <- index(weights_tac)[1:2]
    invest_assets_list <- list(NULL, invest_assets)
    fixed_curr_list <- list(NULL, fixed_curr)
    port_back <- portfolio_backtest_compose(capital, weights_tac, currency, asset_data, series_back_list, rebal_per_in_months = rebal_per,  rebal_dates = NULL, slippage = slippage, commission = commission, invest_assets_list = invest_assets_list, fixed_curr_list = fixed_curr_list)
  }else{
    port_back <- portfolio_backtest(w_port, capital, currency, asset_data, series_back[,c(names(w_port), port_curr)], rebal_per_in_months = rebal_per, weights_xts = weights_tac, slippage = slippage, commission = commission, invest_assets = invest_assets, fixed_curr = fixed_curr)
  }

  total_port <- round(100*as.numeric(tail(port_back$ret_port,1)), 3)
  rets_port <- periodReturn(port_back$cash_port, period = per)
  avg_port <- mean(rets_port)
  vol_port <- sd(rets_port)
  ann_avg_port <- round(avg_port*freq*100, 3)
  ann_vol_port <- round(vol_port*sqrt(freq)*100, 3)
  sharpe_port <- round(avg_port/vol_port, 3)

  te <- active_ret <- ann_te <- info_ratio <- NA
  if(!is.null(w_bench)){
    rebal_dates <- NULL
    if(sync_dates){
      rebal_dates <- index(weights_tac)
    }
    bench_back <- portfolio_backtest(w_bench, capital, currency, asset_data, series_bench[,c(names(w_bench), bench_curr)], rebal_per_in_months = rebal_per, weights_xts = NULL,
                                     rebal_dates = rebal_dates, slippage = slippage, commission = commission)

    total_bench <- round(100*as.numeric(tail(bench_back$ret_port,1)), 3)
    rets_bench <- periodReturn(bench_back$cash_port, period = per)
    avg_bench <- mean(rets_bench)
    ann_avg_bench <- round(avg_bench*freq*100, 3)

    te <- sd(rets_port - rets_bench)

    active_ret <- round(100*(avg_port - avg_bench) * freq, 3)
    active_total_ret <- round(total_port - total_bench, 3)
    ann_te <- round(te*sqrt(freq)*100,3)
    info_ratio <- 0
    if(te > 0){
      info_ratio <- round(active_ret/ann_te,3)
    }

    if(total_ret){
      active_ret_aa <- active_total_ret
    }else{
      active_ret_aa <- active_ret
    }

    if(!is.null(invest_assets)){
      series_back_aa <- series_merge(series_list, c(index(series_back)[1], tail(index(series_back), 1)), asset_data, currency, asset_names, bench_curr, convert_to_ref = FALSE)
      port_back_aa <- portfolio_backtest(w_port, capital, currency, asset_data, series_back_aa[,c(names(w_port), bench_curr)], rebal_per_in_months = rebal_per, weights_xts = weights_tac, slippage = slippage, commission = commission)
      total_port_aa <- round(100*as.numeric(tail(port_back_aa$ret_port,1)), 3)
      rets_port_aa <- periodReturn(port_back_aa$cash_port, period = per)
      avg_port_aa <- mean(rets_port_aa)
      #ann_avg_port <- round(avg_port_aa*freq*100, 3)
      if(total_ret){
        active_ret_aa <- round(total_port_aa - total_bench, 3)
        active_ret_ss <- active_total_ret - active_ret_aa
      }else{
        active_ret_aa <- round(100*(avg_port_aa - avg_bench) * freq, 3)
        active_ret_ss <- active_ret - active_ret_aa
      }
    }else{
      active_ret_ss <- 0
    }
  }

  summ_df <- t(c(total_bench, total_port, ann_avg_bench, ann_avg_port, ann_vol_port, sharpe_port, active_ret, ann_te, info_ratio, active_ret_aa, active_ret_ss))
  colnames(summ_df) <- header_df
  rownames(summ_df) <- port_name
  return(summ_df)
}
