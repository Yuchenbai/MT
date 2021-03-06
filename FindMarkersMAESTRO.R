#' Identify differential features of single-cell transcriptome and regulome data for given cluster
#'
#' Identify differential features of single-cell data (genes for transcriptome and peaks for regulome) for given cluster. Modified from Seurat FindMarkers function.
#'
#' @docType methods
#' @name FindMarkersMAESTRO
#' @rdname FindMarkersMAESTRO
#'
#' @param object Seurat object generated by \code{\link{CreateSeuratObject}} function.
#' @param ident.1 The identy of interested cluster, default is 0.
#' @param ident.2 A second identity of cluster for comparison; if \code{NULL},
#' use all other cells for comparison. Default is \code{NULL}.
#' @param test.use Method to use to identify differential genes or peaks. Default is "presto", a fast version of Wilcoxon Rank Sum test.
#' "presto" produces exactly the same result as "wilcox", but "presto" is much faster.
#' For scATAC-seq, "t" test is another option. For scRNA-seq, other available options are "bimod",
#' "roc", "t", "negbinom", "poisson", "LR", "MAST", "DESeq2", which supported by Seurat \code{link{FindMarkers}} function.
#' @param slot Slot to pull data from; note that if test.use is "negbinom", "poisson", or "DESeq2", 
#' slot will be set to "counts". Default is "data"
#' @param features Features to use. Default is to use all features.
#' @param min.pct Only test features that are detected in a minimum fraction of min.pct cells 
#' in either of the two populations. For genes, default is 0.1.
#' @param logfc.threshold Only test features which show X-fold difference (log-scale)
#' between two group of cells. For genes, default is 0.25.
#' @param latent.vars Variables to test, used only when test.use is one of 'LR', 'negbinom', 'poisson', or 'MAST'
#' @param min.cells.feature Minimum number of cells expressing the feature in at least one of the two groups, 
#' currently only used for poisson and negative binomial tests. Default is 3.
#' @param min.cells.group Minimum number of cells in one of the groups. Default is 3.
#' @param only.pos Only return positive markers, default is FALSE.
#' @param verbose Print a progress bar, default is TRUE.
#'
#' @author Dongqing Sun, Chenfei Wang
#'
#' @return A dataframe containing a ranked list of pytative markers and 
#' associated statics(p-value, ROC score, etc.)
#'
#' @importFrom Seurat GetAssayData MinMax WhichCells
#' @importFrom future nbrOfWorkers
#' @importFrom pbapply pbsapply
#' @importFrom future.apply future_sapply
#' @export
#' 

FindMarkersMAESTRO <- function(object, ident.1 = 0, ident.2 = NULL,test.use = 'presto', 
                               slot = "data", features = NULL, min.pct = 0.1, logfc.threshold = 0.25,
                               latent.vars = NULL, min.cells.feature = 3, min.cells.group = 3,
                               only.pos = FALSE, verbose = TRUE){
  features = if(is.null(features)){rownames(object)} else {features}
  methods.noprefiliter <- c("DESeq2")
  if (test.use %in% methods.noprefiliter) {
    features <- rownames(x = object)
    min.diff.pct <- -Inf
    logfc.threshold <- 0
  }
  
  cells.1 = WhichCells(object = object, idents = ident.1)
  if(is.null(ident.2)){
    cells.2 = setdiff(colnames(object), cells.1)
  } else{
    cells.2 = WhichCells(object = object, idents = ident.2)
  }
  
  methods.count <- c("negbinom", "poisson", "DESeq2")
  slot = ifelse(test.use %in% methods.count, "counts", slot)
  data = GetAssayData(object, slot = slot)[features,c(cells.1, cells.2)]
  
  # feature selection based on percentage
  pct.1 = round(Matrix::rowSums(data[features, cells.1, drop = FALSE] > 0)/length(cells.1), digits = 3)
  pct.2 = round(Matrix::rowSums(data[features, cells.2, drop = FALSE] > 0)/length(cells.2), digits = 3)
  
  pct.ifmax = pct.1 > pct.2
  pct.max = pct.2
  pct.max[which(pct.ifmax)] = pct.1[which(pct.ifmax)]
  features = features[pct.max > min.pct]
  if (length(features) == 0) {
    stop("No features pass min.pct threshold")
  }
  
  # feature selection based on average difference
  if (slot != "scale.data"){
    if (slot == "data"){
      data.1 = log(Matrix::rowMeans(expm1(data[features, cells.1, drop = FALSE])) + 1)
      data.2 = log(Matrix::rowMeans(expm1(data[features, cells.2, drop = FALSE])) + 1)
    } else {
      data.1 = log(Matrix::rowMeans(data[features, cells.1, drop = FALSE]) + 1)
      data.2 = log(Matrix::rowMeans(data[features, cells.2, drop = FALSE]) + 1)
    }
  } else {
    data.1 = Matrix::rowMeans(data[features, cells.1, drop = FALSE])
    data.2 = Matrix::rowMeans(data[features, cells.2, drop = FALSE])
  }

  data.diff = (data.1 - data.2)
  features = if(only.pos){names(which(data.diff > logfc.threshold))} else{names(which(abs(data.diff) > logfc.threshold))}
  if (length(features) == 0) {
    stop("No features pass logfc threshold")
  }
  
  if (!(test.use %in% c('negbinom', 'poisson', 'MAST', "LR")) && !is.null(x = latent.vars)) {
    warning(
      "'latent.vars' is only used for 'negbinom', 'poisson', 'LR', and 'MAST' tests",
      call. = FALSE,
      immediate. = TRUE
    )
  }
  
  # DE test
  test.res.pval = switch(
    test.use,
    'presto' = prestoTest(
      data.use = data[features, c(cells.1, cells.2), drop = FALSE],
      cells.1 = cells.1,
      cells.2 = cells.2
    ),
    'wilcox' = WilcoxDETest(
      data.use = data[features, c(cells.1, cells.2), drop = FALSE],
      cells.1 = cells.1,
      cells.2 = cells.2,
      verbose = verbose
    ),
    'bimod' = DiffExpTest(
      data.use = data[features, c(cells.1, cells.2), drop = FALSE],
      cells.1 = cells.1,
      cells.2 = cells.2,
      verbose = verbose
    ),
    'roc' = MarkerTest(
      data.use = data[features, c(cells.1, cells.2), drop = FALSE],
      cells.1 = cells.1,
      cells.2 = cells.2,
      verbose = verbose
    ),
    't' = DiffTTest(
      data.use = data[features, c(cells.1, cells.2), drop = FALSE],
      cells.1 = cells.1,
      cells.2 = cells.2,
      verbose = verbose
    ),
    'negbinom' = GLMDETest(
      data.use = data[features, c(cells.1, cells.2), drop = FALSE],
      cells.1 = cells.1,
      cells.2 = cells.2,
      min.cells = min.cells.feature,
      latent.vars = latent.vars,
      test.use = test.use,
      verbose = verbose
    ),
    'poisson' = GLMDETest(
      data.use = data[features, c(cells.1, cells.2), drop = FALSE],
      cells.1 = cells.1,
      cells.2 = cells.2,
      min.cells = min.cells.feature,
      latent.vars = latent.vars,
      test.use = test.use,
      verbose = verbose
    ),
    'MAST' = MASTDETest(
      data.use = data[features, c(cells.1, cells.2), drop = FALSE],
      cells.1 = cells.1,
      cells.2 = cells.2,
      latent.vars = latent.vars,
      verbose = verbose
    ),
    "DESeq2" = DESeq2DETest(
      data.use = data[features, c(cells.1, cells.2), drop = FALSE],
      cells.1 = cells.1,
      cells.2 = cells.2,
      verbose = verbose
    ),
    "LR" = LRDETest(
      data.use = data[features, c(cells.1, cells.2), drop = FALSE],
      cells.1 = cells.1,
      cells.2 = cells.2,
      latent.vars = latent.vars,
      verbose = verbose
    ),
    stop("Unknown test: ", test.use))
  
  test.res <- test.res.pval
  test.res$avg_logFC <- data.diff[rownames(test.res)]
  test.res <- cbind(test.res, cbind(pct.1,pct.2)[rownames(test.res), , drop = FALSE])
  if(test.use == "roc"){
    test.res <- test.res[order(-test.res$power, -test.res[, "avg_logFC"]), ]
  }else{
    test.res <- test.res[order(test.res$p_val, -test.res[, "avg_logFC"]), ]
    test.res$p_val_adj <- p.adjust(p = test.res$p_val, method = "bonferroni", n = nrow(x = object))
  }
  return(test.res)
}

prestoTest <- function(
  data.use,
  cells.1,
  cells.2
){
  group.info <- data.frame(row.names = c(cells.1, cells.2))
  group.info[cells.1, "group"] <- "Group1"
  group.info[cells.2, "group"] <- "Group2"
  group.info = as.character(unlist(group.info))
  presto.res = presto::wilcoxauc(data.use, group.info)
  res = presto.res[presto.res$group == "Group1", c("feature", "pval")]
  return(data.frame(p_val = res$pval, row.names = res$feature))
}

WilcoxDETest <- function(
  data.use,
  cells.1,
  cells.2,
  verbose = TRUE
) {
  group.info <- data.frame(row.names = c(cells.1, cells.2))
  group.info[cells.1, "group"] <- "Group1"
  group.info[cells.2, "group"] <- "Group2"
  group.info[, "group"] <- factor(x = group.info[, "group"])
  data.use <- data.use[, rownames(x = group.info), drop = FALSE]
  my.sapply <- ifelse(verbose && nbrOfWorkers() == 1, pbsapply, future_sapply)
  p_val <- my.sapply(
    X = 1:nrow(x = data.use),
    FUN = function(x) {
      return(wilcox.test(data.use[x, ] ~ group.info[, "group"])$p.value)
    }
  )
  return(data.frame(p_val, row.names = rownames(x = data.use)))
}

DiffExpTest <- function(
  data.use,
  cells.1,
  cells.2,
  verbose = TRUE
) {
  my.sapply <- ifelse(verbose && nbrOfWorkers() == 1, pbsapply, future_sapply)
  p_val <- unlist(
    x = my.sapply(
      X = 1:nrow(x = data.use),
      FUN = function(x) {
        return(DifferentialLRT(
          x = as.numeric(x = data.use[x, cells.1]),
          y = as.numeric(x = data.use[x, cells.2])
        ))
      }
    )
  )
  return(data.frame(p_val, row.names = rownames(x = data.use)))
}

DifferentialLRT <- function(x, y, xmin = 0) {
  lrtX <- bimodLikData(x = x)
  lrtY <- bimodLikData(x = y)
  lrtZ <- bimodLikData(x = c(x, y))
  lrt_diff <- 2 * (lrtX + lrtY - lrtZ)
  return(pchisq(q = lrt_diff, df = 3, lower.tail = F))
}

bimodLikData <- function(x, xmin = 0) {
  x1 <- x[x <= xmin]
  x2 <- x[x > xmin]
  xal <- MinMax(
    data = length(x = x2) / length(x = x),
    min = 1e-5,
    max = (1 - 1e-5)
  )
  likA <- length(x = x1) * log(x = 1 - xal)
  mysd <- ifelse(length(x = x2) < 2, 1, sd(x = x2))
  likB <- length(x = x2) * log(x = xal) +
    sum(dnorm(x = x2, mean = mean(x = x2), sd = mysd, log = TRUE))
  return(likA + likB)
}

MarkerTest <- function(
  data.use,
  cells.1,
  cells.2,
  verbose = TRUE
) {
  to.return.AUC <- AUCMarkerTest(
    data1 = data.use[, cells.1, drop = FALSE],
    data2 = data.use[, cells.2, drop = FALSE],
    mygenes = rownames(x = data.use),
    print.bar = verbose
  )
  
  to.return.power <- abs(x = to.return.AUC - 0.5) * 2
  to.return <- data.frame(AUC = to.return.AUC, power = to.return.power, row.names = rownames(data.use))
  to.return <- to.return[rev(x = order(to.return$AUC)), ]
  return(to.return)
}

AUCMarkerTest <- function(data1, data2, mygenes, print.bar = TRUE) {
  AUC <- unlist(x = lapply(
    X = mygenes,
    FUN = function(x) {
      return(DifferentialAUC(
        x = as.numeric(x = data1[x, ]),
        y = as.numeric(x = data2[x, ])
      ))
    }
  ))
  AUC[is.na(x = AUC)] <- 0
  return(AUC)
}

#' @importFrom ROCR performance prediction
DifferentialAUC <- function(x, y) {
  prediction.use <- prediction(
    predictions = c(x, y),
    labels = c(rep(x = 1, length(x = x)), rep(x = 0, length(x = y))),
    label.ordering = 0:1
  )
  perf.use <- performance(prediction.obj = prediction.use, measure = "auc")
  auc.use <- round(x = perf.use@y.values[[1]], digits = 3)
  return(auc.use)
}

DiffTTest <- function(
  data.use,
  cells.1,
  cells.2,
  verbose = TRUE
) {
  my.sapply <- ifelse(
    test = verbose && nbrOfWorkers() == 1,
    yes = pbsapply,
    no = future_sapply
  )
  p_val <- unlist(
    x = my.sapply(
      X = 1:nrow(data.use),
      FUN = function(x) {
        t.test(x = data.use[x, cells.1], y = data.use[x, cells.2])$p.value
      }
    )
  )
  return(data.frame(p_val,row.names = rownames(x = data.use)))
}

#' @importFrom MASS glm.nb
GLMDETest <- function(
  data.use,
  cells.1,
  cells.2,
  min.cells = 3,
  latent.vars = NULL,
  test.use = NULL,
  verbose = TRUE
) {
  group.info <- data.frame(
    group = rep(
      x = c('Group1', 'Group2'),
      times = c(length(x = cells.1), length(x = cells.2))
    )
  )
  rownames(group.info) <- c(cells.1, cells.2)
  group.info[, "group"] <- factor(x = group.info[, "group"])
  latent.vars <- if (is.null(x = latent.vars)) {
    group.info
  } else {
    cbind(x = group.info, latent.vars)
  }
  latent.var.names <- colnames(x = latent.vars)
  my.sapply <- ifelse(
    test = verbose && nbrOfWorkers() == 1,
    yes = pbsapply,
    no = future_sapply
  )
  p_val <- unlist(
    x = my.sapply(
      X = 1:nrow(data.use),
      FUN = function(x) {
        latent.vars[, "GENE"] <- as.numeric(x = data.use[x, ])
        # check that gene is expressed in specified number of cells in one group
        if (sum(latent.vars$GENE[latent.vars$group == "Group1"] > 0) < min.cells &&
            sum(latent.vars$GENE[latent.vars$group == "Group2"] > 0) < min.cells) {
          warning(paste0(
            "Skipping gene --- ",
            x,
            ". Fewer than ",
            min.cells,
            " cells in both clusters."
          ))
          return(2)
        }
        # check that variance between groups is not 0
        if (var(x = latent.vars$GENE) == 0) {
          warning(paste0(
            "Skipping gene -- ",
            x,
            ". No variance in expression between the two clusters."
          ))
          return(2)
        }
        fmla <- as.formula(object = paste(
          "GENE ~",
          paste(latent.var.names, collapse = "+")
        ))
        p.estimate <- 2
        if (test.use == "negbinom") {
          try(
            expr = p.estimate <- summary(
              object = glm.nb(formula = fmla, data = latent.vars)
            )$coef[2, 4],
            silent = TRUE
          )
          return(p.estimate)
        } else if (test.use == "poisson") {
          return(summary(object = glm(
            formula = fmla,
            data = latent.vars,
            family = "poisson"
          ))$coef[2,4])
        }
      }
    )
  )
  features.keep <- rownames(data.use)
  if (length(x = which(x = p_val == 2)) > 0) {
    features.keep <- features.keep[-which(x = p_val == 2)]
    p_val <- p_val[!p_val == 2]
  }
  to.return <- data.frame(p_val, row.names = features.keep)
  return(to.return)
}


MASTDETest <- function(
  data.use,
  cells.1,
  cells.2,
  latent.vars = NULL,
  verbose = TRUE
) {
  # Check for MAST
  if (!('MAST' %in% installed.packages())) {
    stop("Please install MAST - learn more at https://github.com/RGLab/MAST")
  }
  if (length(x = latent.vars) > 0) {
    latent.vars <- scale(x = latent.vars)
  }
  group.info <- data.frame(row.names = c(cells.1, cells.2))
  latent.vars <- if(!is.null(latent.vars)) {latent.vars} else {group.info}
  group.info[cells.1, "group"] <- "Group1"
  group.info[cells.2, "group"] <- "Group2"
  group.info[, "group"] <- factor(x = group.info[, "group"])
  latent.vars.names <- c("condition", colnames(x = latent.vars))
  latent.vars <- cbind(latent.vars, group.info)
  latent.vars$wellKey <- rownames(x = latent.vars)
  fdat <- data.frame(rownames(x = data.use))
  colnames(x = fdat)[1] <- "primerid"
  rownames(x = fdat) <- fdat[, 1]
  sca <- MAST::FromMatrix(
    exprsArray = as.matrix(x = data.use),
    cData = latent.vars,
    fData = fdat
  )
  cond <- factor(x = SummarizedExperiment::colData(sca)$group)
  cond <- relevel(x = cond, ref = "Group1")
  SummarizedExperiment::colData(sca)$condition <- cond
  fmla <- as.formula(
    object = paste0(" ~ ", paste(latent.vars.names, collapse = "+"))
  )
  zlmCond <- MAST::zlm(formula = fmla, sca = sca)
  summaryCond <- summary(object = zlmCond, doLRT = 'conditionGroup2')
  summaryDt <- summaryCond$datatable
  summaryDt <- as.data.frame(summaryDt)
  # fcHurdle <- merge(
  #   summaryDt[contrast=='conditionGroup2' & component=='H', .(primerid, `Pr(>Chisq)`)], #hurdle P values
  #   summaryDt[contrast=='conditionGroup2' & component=='logFC', .(primerid, coef, ci.hi, ci.lo)], by='primerid'
  # ) #logFC coefficients
  # fcHurdle[,fdr:=p.adjust(`Pr(>Chisq)`, 'fdr')]
  p_val <- summaryDt[which(summaryDt[, "component"] == "H"), 4]
  genes.return <- summaryDt[which(summaryDt[, "component"] == "H"), 1]
  # p_val <- subset(summaryDt, component == "H")[, 4]
  # genes.return <- subset(summaryDt, component == "H")[, 1]
  to.return <- data.frame(p_val, row.names = genes.return)
  return(to.return)
}

DESeq2DETest <- function(
  data.use,
  cells.1,
  cells.2,
  verbose = TRUE
) {
  if (!('DESeq2' %in% installed.packages())) {
    stop("Please install DESeq2 - learn more at https://bioconductor.org/packages/release/bioc/html/DESeq2.html")
  }
  group.info <- data.frame(row.names = c(cells.1, cells.2))
  group.info[cells.1, "group"] <- "Group1"
  group.info[cells.2, "group"] <- "Group2"
  group.info[, "group"] <- factor(x = group.info[, "group"])
  group.info$wellKey <- rownames(x = group.info)
  dds1 <- DESeq2::DESeqDataSetFromMatrix(
    countData = data.use,
    colData = group.info,
    design = ~ group
  )
  dds1 <- DESeq2::estimateSizeFactors(object = dds1)
  dds1 <- DESeq2::estimateDispersions(object = dds1, fitType = "local")
  dds1 <- DESeq2::nbinomWaldTest(object = dds1)
  res <- DESeq2::results(
    object = dds1,
    contrast = c("group", "Group1", "Group2"),
    alpha = 0.05,
  )
  to.return <- data.frame(p_val = res$pvalue, row.names = rownames(res))
  return(to.return)
}

#' @importFrom lmtest lrtest
LRDETest <- function(
  data.use,
  cells.1,
  cells.2,
  latent.vars = NULL,
  verbose = TRUE
) {
  group.info <- data.frame(row.names = c(cells.1, cells.2))
  group.info[cells.1, "group"] <- "Group1"
  group.info[cells.2, "group"] <- "Group2"
  group.info[, "group"] <- factor(x = group.info[, "group"])
  data.use <- data.use[, rownames(group.info), drop = FALSE]
  latent.vars <- latent.vars[rownames(group.info), , drop = FALSE]
  my.sapply <- ifelse(
    test = verbose && nbrOfWorkers() == 1,
    yes = pbsapply,
    no = future_sapply
  )
  p_val <- my.sapply(
    X = 1:nrow(x = data.use),
    FUN = function(x) {
      if (is.null(x = latent.vars)) {
        model.data <- cbind(GENE = data.use[x, ], group.info)
        fmla <- as.formula(object = "group ~ GENE")
        fmla2 <- as.formula(object = "group ~ 1")
      } else {
        model.data <- cbind(GENE = data.use[x, ], group.info, latent.vars)
        fmla <- as.formula(object = paste(
          "group ~ GENE +",
          paste(colnames(x = latent.vars), collapse = "+")
        ))
        fmla2 <- as.formula(object = paste(
          "group ~",
          paste(colnames(x = latent.vars), collapse = "+")
        ))
      }
      model1 <- glm(formula = fmla, data = model.data, family = "binomial")
      model2 <- glm(formula = fmla2, data = model.data, family = "binomial")
      lrtest <- lrtest(model1, model2)
      return(lrtest$Pr[2])
    }
  )
  to.return <- data.frame(p_val, row.names = rownames(data.use))
  return(to.return)
}


