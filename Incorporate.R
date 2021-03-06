#' Incorparation of scATAC-seq clusters with scRNA-seq clusters
#'
#' Incorparation of scATAC-seq clusters with scRNA-seq clusters, generate the cell-coembedding visualizations, also transfer the celltypes from scRNA-seq to scATAC-seq annotations. 
#'
#' @docType methods
#' @name Incorporate
#' @rdname Incorporate
#'
#' @param ATAC Seurat object of clustered scATAC-seq dataset, generated by \code{\link{ATACRunSeurat}} function.
#' @param RNA Seurat object of clustered scRNA-seq dataset, generated by \code{\link{RNARunSeurat}} function.
#' @param RPmatrix Data frame of regulatory potential matrix generated by MAESTRO. With genes as rows and cells as columns,
#' and gene RP score as values. Can be ignored if \code{\link{ATACAnnotateCelltype}} have already been run.
#' @param project Output project name. Default is "MAESTRO.coembedded".
#' @param method Method to do integration, MAESTRO or Seurat. If "MAESTRO", gene RP score will be used to quantify the gene activity for scATAC-seq.
#' If "Seurat" is set, \code{\link{CreateGeneActivityMatrix}} from Seurat will be used to model the gene activity.
#' @param dims.use Number of dimensions used for PCA and UMAP analysis. Default is 1:30, use the first 30 PCs.
#' @param RNA.res Clusterig resolution used for the scRNA-seq dataset, should keep the same with the input RNA object. Default is 0.6.
#' @param ATAC.res Clustering resolution used for the scATAC-seq dataset, should keep the sampe with the input ATAC object. Default is 0.6.
#'
#' @author Chenfei Wang
#'
#' @return A combined Seurat object with RNA dataset, ATAC dataset, gene activity dataset, combined UMAP analysis and clustering information. A tsv file for the cell meta information. 
#'
#'
#' @examples
#' data(pbmc.RNA)
#' data(pbmc.ATAC)
#' data(pbmc.RP)
#'
#' pbmc.RNA.res <- RNARunSeurat(inputMat = pbmc.RNA, project = "PBMC.scRNA.Seurat")
#' pbmc.RNA.res$RNA <- RNAAnnotateCelltype(pbmc.RNA.res$RNA, pbmc.RNA.res$genes, human.immune.CIBERSORT, min.score = 0.05)
#' pbmc.ATAC.res <- ATACRunSeurat(inputMat = pbmc.ATAC, project = "PBMC.scATAC.Seurat")
#' pbmc.ATAC.res$ATAC <- ATACAnnotateCelltype(pbmc.ATAC.res$ATAC, pbmc.RP, human.immune.CIBERSORT, min.score = 0.1, genes.cutoff = 1E-3)
#' pbmc.coembedded.cluster <- Incorporate(RNA = pbmc.RNA.res$RNA, ATAC = pbmc.ATAC.res$ATAC, project = "PBMC.coembedded")
#' str(pbmc.coembedded.cluster)
#'
#' @importFrom Seurat CreateAssayObject CreateGeneActivityMatrix CreateSeuratObject DimPlot FindTransferAnchors FindVariableFeatures GetAssayData NormalizeData RunPCA RunUMAP ScaleData SubsetData TransferData VariableFeatures 
#' @importFrom ggplot2 ggsave
#' @export

Incorporate <- function(RNA, ATAC, RPmatrix = NULL, project = "MAESTRO.coembedding", method = "MAESTRO", annotation.file, dims.use = 1:30, RNA.res = 0.6, ATAC.res = 0.6)
{
  require(Seurat)
  ATAC$tech <- "ATAC"
  RNA$tech <- "RNA"
  
  if(is.null(ATAC[["ACTIVITY"]])&method!="Seurat"){
     RPmatrix <- RPmatrix[,intersect(colnames(ATAC), colnames(RPmatrix))]
     ATAC <- SubsetData(ATAC, cells = intersect(colnames(ATAC), colnames(RPmatrix)))
     ATAC[["ACTIVITY"]] <- CreateAssayObject(counts = RPmatrix)
     DefaultAssay(ATAC) <- "ACTIVITY"
     ATAC <- FindVariableFeatures(ATAC)
     ATAC <- NormalizeData(ATAC)
     ATAC <- ScaleData(ATAC)
  }
  if(method=="Seurat"){
     activity.matrix <- CreateGeneActivityMatrix(peak.matrix = GetAssayData(ATAC, slot = "counts", assay = "ATAC"), annotation.file = annotation.file,  seq.levels = c(1:22, "X", "Y"), upstream = 2000, verbose = TRUE)
     activity.matrix <- activity.matrix[,intersect(colnames(ATAC), colnames(activity.matrix))]
     ATAC <- SubsetData(ATAC, cells = intersect(colnames(ATAC), colnames(activity.matrix)))
     ATAC[["ACTIVITY"]] <- CreateAssayObject(counts = activity.matrix)
     DefaultAssay(ATAC) <- "ACTIVITY"
     ATAC <- FindVariableFeatures(ATAC)
     ATAC <- NormalizeData(ATAC)
     ATAC <- ScaleData(ATAC)
  }

  DefaultAssay(ATAC) <- "ACTIVITY"
  transfer.anchors <- FindTransferAnchors(reference = RNA, query = ATAC, features = VariableFeatures(object = RNA), 
                      reference.assay = "RNA", query.assay = "ACTIVITY", reduction = "cca")
  celltype.predictions <- TransferData(anchorset = transfer.anchors, refdata = RNA$assign.ident, weight.reduction = ATAC[["lsi"]])
  ATAC@meta.data$assign.ident <- celltype.predictions$predicted.id
  ATAC@meta.data$prediction.score.max <- celltype.predictions$prediction.score.max

  genes.use <- VariableFeatures(RNA)
  refdata <- GetAssayData(RNA, assay = "RNA", slot = "data")[genes.use, ]
  imputation <- TransferData(anchorset = transfer.anchors, refdata = refdata, weight.reduction = ATAC[["lsi"]])
  ATAC[["RNA"]] <- imputation

  CombinedObj <- merge(x = RNA, y = ATAC)
  CombinedObj@project.name <- project
  CombinedObj <- ScaleData(CombinedObj, features = genes.use, do.scale = FALSE)
  CombinedObj <- RunPCA(CombinedObj, features = genes.use, verbose = FALSE)
  CombinedObj <- RunUMAP(CombinedObj, dims = dims.use)

  p1 <- DimPlot(CombinedObj, reduction = "umap", group.by = "tech", repel = TRUE)
  ggsave(file.path(paste0(CombinedObj@project.name, "_source.png")), p1, width=5, height=4)
  p2 <- DimPlot(CombinedObj, reduction = "umap", group.by = paste0("RNA_snn_res.", RNA.res), cells = rownames(CombinedObj@meta.data[which(CombinedObj@meta.data[,'tech']=='RNA'),]), label = TRUE, repel = TRUE)
  ggsave(file.path(paste0(CombinedObj@project.name, "_RNAonly.png")), p2, width=5, height=4)
  p3 <- DimPlot(CombinedObj, reduction = "umap", group.by = paste0("ATAC_snn_res.", ATAC.res), cells = rownames(CombinedObj@meta.data[which(CombinedObj@meta.data[,'tech']=='ATAC'),]), label = TRUE, repel = TRUE)
  ggsave(file.path(paste0(CombinedObj@project.name, "_ATAConly.png")), p3, width=5, height=4)
  p4 <- DimPlot(object = CombinedObj, pt.size = 0.15, group.by = "assign.ident", label = TRUE, label.size = 3, repel = TRUE)
  ggsave(file.path(paste0(CombinedObj@project.name, "_annotated.png")), p4, width=6, height=4)
  
  write.table(CombinedObj@meta.data, file.path(paste0(CombinedObj@project.name, "_metadata.tsv")), quote=F, sep="\t")
  return(CombinedObj)
}


