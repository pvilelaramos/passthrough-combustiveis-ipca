# Roda o projeto de ponta a ponta ---------------------------------------------
# Uso:
#   Rscript run.R            # baixa os dados (IBGE, BCB, FRED)
#   Rscript run.R --offline  # usa data/processado/base_mensal.csv

source("R/dados.R")
source("R/lp.R")
source("R/graficos.R")

args <- commandArgs(trailingOnly = TRUE)
arquivo_base <- "data/processado/base_mensal.csv"

if ("--offline" %in% args) {
  base <- read.csv(arquivo_base)
  base$data <- as.Date(base$data)
} else {
  base <- montar_base()
  dir.create(dirname(arquivo_base), recursive = TRUE, showWarnings = FALSE)
  write.csv(base, arquivo_base, row.names = FALSE)
}
message(sprintf("Base: %d meses (%s a %s)", nrow(base),
                format(min(base$data), "%m/%Y"), format(max(base$data), "%m/%Y")))

b <- preparar(base)
irf_gas <- lp_regimes(b, "y_gasolina")
irf_ipca <- lp_regimes(b, "y_ipca")

dir.create("figures", showWarnings = FALSE)
dir.create("resultados", showWarnings = FALSE)
write.csv(rbind(irf_gas, irf_ipca), "resultados/irf.csv", row.names = FALSE)

grafico_irf(irf_gas, "Repasse do petróleo para a gasolina no IPCA", "figures/irf_gasolina.png")
grafico_irf(irf_ipca, "Repasse do petróleo para o IPCA cheio", "figures/irf_ipca.png")
tabela_resumo(irf_gas, irf_ipca, base, "resultados/resumo.md")

cat(readLines("resultados/resumo.md"), sep = "\n")
