---
title: "AnnotationEnrichment"
author: "Reedliu"
date: "2019-01-20"
---
  
### 非模式生物
  
# 方法一：利用AnnotationHub
# 以棉铃虫为例
hub <- AnnotationHub()
# 调用图形界面查看物种
display(hub) 
# 或者根据物种拉丁文名称查找
query(hub,"helicoverpa")
#   'object[["AH66950"]]' 

#title                                      
#AH66950 | org.Helicoverpa_armigera.eg.sqlite         
#AH66951 | org.Heliothis_(Helicoverpa)_armigera.eg....
# 这里AH66950是我们需要的
# 然后下载这个sqlite数据库
ha.db <- hub[['AH66950']]

#查看前几个基因（Entrez命名）
head(keys(ha.db))
#查看包含的基因数
length(keys(ha.db)) 
#查看包含多少种ID
columns(ha.db)
#查看前几个基因的ID
select(ha.db, keys(ha.db)[1:3], 
       c("REFSEQ", "SYMBOL"), #想获取的ID
       "ENTREZID")
#保存到文件
saveDb(ha.db, "Harms-AH66950.sqlite")

#之后再使用直接加载进来
maize.db <- loadDb("Harms-AH66950.sqlite")

# 方法二：利用AnnotationForge
# 以芝麻为例

# first:得到pathway2name, ko2pathway
if(F){
    # https://www.genome.jp/kegg-bin/get_htext?ko00001
    library(jsonlite)
    library(purrr)
    library(RCurl)
    
    update_kegg <- function(json = "ko00001.json") {
        pathway2name <- tibble(Pathway = character(), Name = character())
        ko2pathway <- tibble(Ko = character(), Pathway = character())
        
        kegg <- fromJSON(json)
        
        for (a in seq_along(kegg[["children"]][["children"]])) {
            A <- kegg[["children"]][["name"]][[a]]
            
            for (b in seq_along(kegg[["children"]][["children"]][[a]][["children"]])) {
                B <- kegg[["children"]][["children"]][[a]][["name"]][[b]] 
                
                for (c in seq_along(kegg[["children"]][["children"]][[a]][["children"]][[b]][["children"]])) {
                    pathway_info <- kegg[["children"]][["children"]][[a]][["children"]][[b]][["name"]][[c]]
                    
                    pathway_id <- str_match(pathway_info, "ko[0-9]{5}")[1]
                    pathway_name <- str_replace(pathway_info, " \\[PATH:ko[0-9]{5}\\]", "") %>% str_replace("[0-9]{5} ", "")
                    pathway2name <- rbind(pathway2name, tibble(Pathway = pathway_id, Name = pathway_name))
                    
                    kos_info <- kegg[["children"]][["children"]][[a]][["children"]][[b]][["children"]][[c]][["name"]]
                    
                    kos <- str_match(kos_info, "K[0-9]*")[,1]
                    
                    ko2pathway <- rbind(ko2pathway, tibble(Ko = kos, Pathway = rep(pathway_id, length(kos))))
                }
            }
        }
        
        save(pathway2name, ko2pathway, file = "kegg_info.RData")
    }
    
    update_kegg(json = "ko00001.json")
    
}
# second: make org.db
library(tidyverse)
library(stringr)
library(KEGGREST)
library(AnnotationForge)

makeOrgPackageFromEmapper <- function(egg_f, 
                                      author, 
                                      tax_id = "0", 
                                      genus = "default", 
                                      species = "default") {
    
    # read emapper result
    egg <- read.csv(egg_f, sep = "\t")
egg[egg==""]<-NA #这个代码来自花花的指导(将空行变成NA，方便下面的去除)
    
    # extract gene name from emapper
    gene_info <- egg %>%
        dplyr::select(GID = query_name, GENENAME = `eggNOG annot`) %>% na.omit()
    
    # extract go annotation from emapper
    gterms <- egg %>%
        dplyr::select(query_name, GO_terms) %>% na.omit()
    
    # 先构建一个空的数据框(弄好大体的架构，表示其中要有GID =》query_name，GO =》GO号， EVIDENCE =》默认IDA)
    # 关于IEA：就是一个标准，除了这个标准以外还有许多。IEA就是表示我们的注释是自动注释，无需人工检查 
    # http://wiki.geneontology.org/index.php/Inferred_from_Electronic_Annotation_(IEA)
    # 两种情况下需要用IEA：
    # 1. manually constructed mappings between external classification systems and GO terms； 
    # 2.automatic transfer of annotation to orthologous gene products.
    gene2go = data.frame(GID = character(),
                         GO = character(),
                         EVIDENCE = character())
    
    # 然后向其中填充：注意到有的query_name对应多个GO，因此我们以GO号为标准，每一行只能有一个GO号，但query_name和Evidence可以重复
    for (row in 1:nrow(gterms)) {
      gene_terms <- str_split(gterms[row,"GO_terms"], ",", simplify = FALSE)[[1]]  
      gene_id <- gterms[row, "query_name"][[1]]
      tmp <- data_frame(GID = rep(gene_id, length(gene_terms)),
                              GO = gene_terms,
                              EVIDENCE = rep("IEA", length(gene_terms)))
        gene2go <- rbind(gene2go, tmp)
    }


    
    # extract kegg pathway annotation from emapper
    gene2ko <- egg %>%
        dplyr::select(GID = query_name, Ko = KEGG_KOs) %>%
        na.omit()
    
    load(file = "kegg_info.RData")
    gene2pathway <- gene2ko %>% left_join(ko2pathway, by = "Ko") %>% 
        dplyr::select(GID, Pathway) %>%
        na.omit()
    
    # make OrgDb
    makeOrgPackage(gene_info=gene_info,
                   go=gene2go,
                   ko=gene2ko,
                   pathway=gene2pathway,
                   # gene2pathway=gene2pathway,
                   version="0.0.2",
                   maintainer=author,
                   author=author,
                   outputDir = ".",
                   tax_id=tax_id,
                   genus=genus,
                   species=species,
                   goTable="go")
    
    my_orgdb <- str_c("org.", str_to_upper(str_sub(genus, 1, 1)) , species, ".eg.db", sep = "")
    return(my_orgdb)
}

my_orgdb <- makeOrgPackageFromEmapper("diamond.emapper.annotations", 
                                      "reedliu <jieandze1314@gmail.com>", 
                                      tax_id = "4182", 
                                      genus = "Sesamum", 
                                      species = "indicum")

if (requireNamespace(my_orgdb, quietly = TRUE))
    remove.packages(my_orgdb)
install.packages(my_orgdb, repos = NULL)
