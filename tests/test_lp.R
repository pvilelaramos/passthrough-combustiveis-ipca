# Teste com dados simulados: as projeções locais recuperam o repasse verdadeiro?
# Rodar com:  Rscript tests/test_lp.R

source("R/lp.R")

set.seed(42)
datas <- seq(as.Date("2006-07-01"), as.Date("2026-06-01"), by = "month")
n <- length(datas)
regime <- regime_petrobras(datas)
choque <- rnorm(n, 0, 8)                       # % ao mês
# Repasse verdadeiro para a gasolina: 0,05 (controle), 0,30 (PPI), 0,15 (nova)
repasse <- c(0.05, 0.30, 0.15)[as.integer(regime)]
gas_var <- 0.4 + repasse * choque + rnorm(n, 0, 0.8)
ipca_var <- 0.35 + 0.05 * gas_var + rnorm(n, 0, 0.15)
brent_brl <- 200 * exp(cumsum(choque / 100))

base <- data.frame(data = datas, ipca_var = ipca_var, gasolina_var = gas_var,
                   gasolina_peso = 5, brent_brl = brent_brl)
b <- preparar(base)
irf <- lp_regimes(b, "y_gasolina", H = 3)
imp <- irf[irf$h == 0, ]
print(imp[, c("regime", "beta", "inf", "sup")])

esperado <- c(0.05, 0.30, 0.15)
stopifnot(all(abs(imp$beta - esperado) < 0.06))
cat("OK: repasse de impacto recuperado nos três regimes\n")
