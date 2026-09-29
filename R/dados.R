# Coleta de dados -------------------------------------------------------------
# IPCA e IPCA-gasolina (IBGE/SIDRA), câmbio (BCB/SGS), Brent (FMI via FRED).

library(jsonlite)

CABECALHOS <- c(
  "User-Agent" = paste(
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36",
    "(KHTML, like Gecko) Chrome/126.0 Safari/537.36"
  ),
  "Accept" = "application/json, text/csv"
)

# Baixa um arquivo com novas tentativas (APIs públicas oscilam)
baixar <- function(url, tentativas = 4) {
  destino <- tempfile()
  for (i in seq_len(tentativas)) {
    ok <- tryCatch({
      download.file(url, destino, quiet = TRUE, method = "libcurl",
                    headers = CABECALHOS, mode = "wb")
      # Às vezes a API devolve uma página de erro (HTML/XML) com status 200
      inicio <- trimws(readChar(destino, 200, useBytes = TRUE))
      if (grepl("^<", inicio)) stop("resposta não é JSON/CSV: ", substr(inicio, 1, 80))
      TRUE
    }, error = function(e) {
      message(sprintf("  tentativa %d/%d falhou: %s", i, tentativas, conditionMessage(e)))
      FALSE
    }, warning = function(w) {
      message(sprintf("  tentativa %d/%d falhou: %s", i, tentativas, conditionMessage(w)))
      FALSE
    })
    if (ok) return(destino)
    Sys.sleep(5 * i)
  }
  stop("Não foi possível baixar: ", url)
}

ler_json <- function(url) {
  arq <- baixar(url)
  if (file.size(arq) == 0) return(list())
  fromJSON(arq, simplifyVector = TRUE)
}

primeiro_dia <- function(x) as.Date(format(x, "%Y-%m-01"))

# BCB/SGS ------------------------------------------------------------------------
sgs <- function(codigo, inicio = as.Date("2006-01-01"), fim = Sys.Date()) {
  partes <- list()
  ini <- inicio
  while (ini <= fim) {
    fim_jan <- min(as.Date(sprintf("%d-12-31", as.integer(format(ini, "%Y")) + 4)), fim)
    url <- sprintf(
      "https://api.bcb.gov.br/dados/serie/bcdata.sgs.%d/dados?formato=json&dataInicial=%s&dataFinal=%s",
      codigo, format(ini, "%d/%m/%Y"), format(fim_jan, "%d/%m/%Y")
    )
    x <- ler_json(url)
    if (length(x) > 0 && nrow(x) > 0) partes[[length(partes) + 1]] <- x
    ini <- as.Date(sprintf("%d-01-01", as.integer(format(fim_jan, "%Y")) + 1))
  }
  x <- do.call(rbind, partes)
  x <- x[!duplicated(x$data), ]
  x <- data.frame(data = primeiro_dia(as.Date(x$data, "%d/%m/%Y")),
                  valor = as.numeric(x$valor))
  aggregate(valor ~ data, x, mean)
}

# Brent (US$/barril, média mensal, FMI) via FRED ------------------------------------
brent <- function() {
  x <- read.csv(baixar("https://fred.stlouisfed.org/graph/fredgraph.csv?id=POILBREUSDM"),
                na.strings = ".")
  data.frame(data = primeiro_dia(as.Date(x[[1]])), brent_usd = as.numeric(x[[2]]))
}

# IBGE/SIDRA -----------------------------------------------------------------------
# O IPCA por subitem está em três tabelas, uma para cada estrutura de pesos da POF.
TABELAS_IPCA <- c(2938, 1419, 7060)  # jul/2006–dez/2011, 2012–2019, 2020 em diante

# Localiza, nos metadados, a classificação de produtos e as categorias de interesse
categorias_sidra <- function(tabela) {
  meta <- ler_json(sprintf(
    "https://servicodados.ibge.gov.br/api/v3/agregados/%d/metadados", tabela))
  cls <- meta$classificacoes
  for (k in seq_len(nrow(cls))) {
    cats <- cls$categorias[[k]]
    geral <- cats$id[grepl("^[ÍI]ndice geral$", cats$nome, ignore.case = TRUE)]
    gas <- cats$id[grepl("(^|\\.)\\s*Gasolina$", cats$nome, ignore.case = TRUE)]
    if (length(geral) == 1 && length(gas) >= 1) {
      return(list(classificacao = cls$id[k], geral = geral, gasolina = gas[1]))
    }
  }
  stop("Categorias 'Índice geral' e 'Gasolina' não encontradas na tabela ", tabela)
}

# Variação mensal (v63) e peso (v66) para índice geral e gasolina
sidra_ipca <- function(tabela) {
  cat_ <- categorias_sidra(tabela)
  url <- sprintf(
    "https://apisidra.ibge.gov.br/values/t/%d/n1/all/v/63,66/p/all/c%d/%s,%s",
    tabela, cat_$classificacao, cat_$geral, cat_$gasolina
  )
  x <- ler_json(url)
  cab <- unlist(x[1, ]); x <- x[-1, , drop = FALSE]
  k_mes <- names(cab)[cab == "Mês (Código)"]
  k_var <- names(cab)[cab == "Variável (Código)"]
  # coluna da categoria = a que contém os códigos pedidos
  k_cat <- names(x)[vapply(x, function(col) all(col %in% c(cat_$geral, cat_$gasolina)),
                           logical(1))][1]
  d <- data.frame(
    data = as.Date(paste0(x[[k_mes]], "01"), "%Y%m%d"),
    variavel = ifelse(x[[k_var]] == "63", "var", "peso"),
    serie = ifelse(x[[k_cat]] == cat_$geral, "ipca", "gasolina"),
    valor = suppressWarnings(as.numeric(x$V))
  )
  d$nome <- paste(d$serie, d$variavel, sep = "_")
  largo <- reshape(d[, c("data", "nome", "valor")], idvar = "data",
                   timevar = "nome", direction = "wide")
  names(largo) <- sub("^valor\\.", "", names(largo))
  largo[, c("data", "ipca_var", "gasolina_var", "gasolina_peso")]
}

montar_base <- function() {
  message("IBGE: IPCA e gasolina...")
  ipca <- do.call(rbind, lapply(TABELAS_IPCA, function(t) {
    message("  tabela ", t); sidra_ipca(t)
  }))
  ipca <- ipca[!duplicated(ipca$data), ]
  message("BCB: câmbio...")
  cambio <- sgs(1); names(cambio)[2] <- "cambio"
  message("FRED: Brent...")
  base <- Reduce(function(a, b) merge(a, b, by = "data"), list(ipca, cambio, brent()))
  base <- base[order(base$data), ]
  base$brent_brl <- base$brent_usd * base$cambio
  rownames(base) <- NULL
  base
}
