# Gráficos e tabela-resumo ------------------------------------------------------

library(ggplot2)

CORES <- c("Controle de preços" = "#2a78d6", "PPI" = "#eb6834", "Nova estratégia" = "#1baf7a")
TEXTO <- "#0b0b0b"; TEXTO_2 <- "#52514e"; GRADE <- "#e4e3df"; SUPERFICIE <- "#fcfcfb"

tema <- theme_minimal(base_size = 11) +
  theme(
    plot.background = element_rect(fill = SUPERFICIE, colour = NA),
    panel.grid.minor = element_blank(),
    panel.grid.major.x = element_blank(),
    panel.grid.major.y = element_line(colour = GRADE, linewidth = 0.4),
    plot.title = element_text(face = "bold", colour = TEXTO, size = 14),
    plot.subtitle = element_text(colour = TEXTO_2),
    plot.caption = element_text(colour = TEXTO_2, hjust = 0),
    axis.text = element_text(colour = TEXTO_2),
    axis.title = element_text(colour = TEXTO_2),
    strip.text = element_text(face = "bold", colour = TEXTO, hjust = 0),
    legend.position = "top", legend.justification = "left",
    legend.title = element_blank(), legend.text = element_text(colour = TEXTO)
  )

# Resposta a um choque de 10% no Brent em reais, com bandas de 90%
grafico_irf <- function(irf, titulo, destino, escala = 10) {
  d <- irf
  d[, c("beta", "inf", "sup")] <- d[, c("beta", "inf", "sup")] * escala
  g <- ggplot(d, aes(h, beta, colour = regime, fill = regime)) +
    geom_hline(yintercept = 0, colour = TEXTO_2, linewidth = 0.4) +
    geom_ribbon(aes(ymin = inf, ymax = sup), alpha = 0.15, colour = NA) +
    geom_line(linewidth = 1) +
    geom_point(size = 2, shape = 21, stroke = 1, fill = SUPERFICIE) +
    facet_wrap(~regime, nrow = 1) +
    scale_colour_manual(values = CORES) + scale_fill_manual(values = CORES) +
    scale_x_continuous(breaks = seq(0, 12, 3)) +
    labs(
      title = titulo,
      subtitle = sprintf("Resposta acumulada (p.p.) a um choque de %d%% no Brent em reais · bandas de 90%%", escala),
      x = "Meses após o choque", y = NULL,
      caption = "Fontes: IBGE, BCB, EIA/Ipeadata. Projeções locais com erros Newey-West. Elaboração: Pedro Vilela Ramos."
    ) +
    tema + theme(legend.position = "none")
  ggsave(destino, g, width = 11, height = 4.2, dpi = 150, bg = SUPERFICIE)
}

# Tabela em Markdown com h = 0, 3, 6, 12 e o efeito direto implícito
tabela_resumo <- function(irf_gas, irf_ipca, base, destino, escala = 10) {
  b <- preparar(base)
  pesos <- tapply(b$gasolina_peso, b$regime, mean, na.rm = TRUE)
  f <- function(x) formatC(x, format = "f", digits = 2, decimal.mark = ",")
  linhas <- c(
    sprintf("# Resultados: choque de %d%% no Brent em reais", escala), "",
    sprintf("*Gerado em %s. Amostra: %s a %s.*", format(Sys.Date(), "%d/%m/%Y"),
            format(min(base$data), "%m/%Y"), format(max(base$data), "%m/%Y")), "",
    "| Regime | h | IPCA gasolina (p.p.) | IPCA cheio (p.p.) | Efeito direto no IPCA* | Meses no regime |",
    "|---|---:|---:|---:|---:|---:|"
  )
  for (r in REGIMES) for (h in c(0, 3, 6, 12)) {
    g <- irf_gas[irf_gas$regime == r & irf_gas$h == h, ]
    i <- irf_ipca[irf_ipca$regime == r & irf_ipca$h == h, ]
    if (nrow(g) == 0) next
    direto <- g$beta * escala * pesos[[r]] / 100
    sig <- function(x) if (x$inf > 0 || x$sup < 0) "**" else ""
    linhas <- c(linhas, sprintf(
      "| %s | %d | %s%s%s | %s%s%s | %s | %d |", r, h,
      sig(g), f(g$beta * escala), sig(g), sig(i), f(i$beta * escala), sig(i),
      f(direto), g$n_regime
    ))
  }
  linhas <- c(linhas, "",
    "Em **negrito**: intervalo de 90% não contém zero.",
    sprintf("\\* Efeito direto = resposta da gasolina × peso médio da gasolina no IPCA no regime (%s).",
            paste(sprintf("%s: %s%%", names(pesos), f(pesos)), collapse = "; ")),
    "A diferença entre o IPCA cheio e o efeito direto é uma estimativa dos efeitos indiretos",
    "(frete, passagens, outros bens) e de segunda ordem. Como o choque inclui o câmbio,",
    "essa diferença também capta o repasse cambial para outros bens comercializáveis.")
  writeLines(linhas, destino, useBytes = TRUE)
}
