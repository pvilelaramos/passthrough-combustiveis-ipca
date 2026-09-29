# Projeções locais (Jordà, 2005) com coeficientes por regime de preços ----------

library(sandwich)
library(lmtest)

REGIMES <- c("Controle de preços", "PPI", "Nova estratégia")

# Regime de preços da Petrobras vigente em cada mês
regime_petrobras <- function(data) {
  factor(
    ifelse(data < as.Date("2016-10-01"), REGIMES[1],
           ifelse(data < as.Date("2023-05-01"), REGIMES[2], REGIMES[3])),
    levels = REGIMES
  )
}

# Meses com mudanças de tributação que moveram o preço da gasolina sem vir do
# petróleo: greve dos caminhoneiros, teto do ICMS (LC 194/2022), reoneração federal.
MESES_TRIBUTOS <- as.Date(c("2018-06-01", "2022-07-01", "2022-08-01", "2023-03-01"))

# k > 0: defasagem; k < 0: avanço
desloca <- function(x, k) {
  n <- length(x)
  if (k >= 0) c(rep(NA, k), x[seq_len(n - k)]) else c(x[(1 - k):n], rep(NA, -k))
}

# Prepara as variáveis: log-níveis (x100) e choque = variação % do Brent em reais
preparar <- function(base) {
  b <- base[order(base$data), ]
  b$y_ipca <- cumsum(100 * log(1 + b$ipca_var / 100))
  b$y_gasolina <- cumsum(100 * log(1 + b$gasolina_var / 100))
  b$choque <- c(NA, 100 * diff(log(b$brent_brl)))
  b$regime <- regime_petrobras(b$data)
  b$mes <- factor(format(b$data, "%m"))
  for (m in seq_along(MESES_TRIBUTOS)) {
    b[[paste0("trib_", m)]] <- as.numeric(b$data == MESES_TRIBUTOS[m])
  }
  b
}

# Resposta acumulada de y (h = 0..H) a um choque de 1% no Brent em reais,
# com um coeficiente para cada regime:
#   y_{t+h} − y_{t−1} = Σ_r β_{h,r} · choque_t · 1[regime_t = r] + regime_r
#                       + Σ_{l=1..L} (choque_{t−l} + Δy_{t−l}) + mês + tributos + ε
lp_regimes <- function(b, y, H = 12, L = 3, nivel = 0.90) {
  z <- qnorm(1 - (1 - nivel) / 2)
  dy <- c(NA, diff(b[[y]]))
  saida <- list()
  for (h in 0:H) {
    d <- data.frame(dep = desloca(b[[y]], -h) - desloca(b[[y]], 1),
                    regime = b$regime, mes = b$mes)
    for (r in seq_along(REGIMES)) {
      d[[paste0("choque_r", r)]] <- b$choque * (b$regime == REGIMES[r])
    }
    for (l in seq_len(L)) {
      d[[paste0("choque_l", l)]] <- desloca(b$choque, l)
      d[[paste0("dy_l", l)]] <- desloca(dy, l)
    }
    for (v in grep("^trib_", names(b), value = TRUE)) d[[v]] <- b[[v]]
    d <- na.omit(d)
    mod <- lm(dep ~ ., data = d)
    V <- NeweyWest(mod, lag = h + 1, prewhite = FALSE)
    ct <- coeftest(mod, vcov. = V)
    for (r in seq_along(REGIMES)) {
      nome <- paste0("choque_r", r)
      saida[[length(saida) + 1]] <- data.frame(
        resposta = y, h = h, regime = REGIMES[r],
        beta = ct[nome, 1], ep = ct[nome, 2],
        inf = ct[nome, 1] - z * ct[nome, 2], sup = ct[nome, 1] + z * ct[nome, 2],
        n = nrow(d), n_regime = sum(d[[nome]] != 0)
      )
    }
  }
  out <- do.call(rbind, saida)
  out$regime <- factor(out$regime, levels = REGIMES)
  rownames(out) <- NULL
  out
}
