#' FAO data MIR spectral predictions
#' Soil and wheat plant wet chemistry data courtesy of FAO (doc @ https://www.dropbox.com/s/gwk07tanhu86tqj/Silanpaa%20Report.pdf?dl=0)
#' MIR soil data courtesy of ICRAF (2016)
#' M. Walsh, October 2016

# Data setup --------------------------------------------------------------
# Run this first: https://github.com/mgwalsh/Bioavailability/blob/master/FAO_micro_setup.R
# or run ...
# SourceURL <- "https://raw.githubusercontent.com/mgwalsh/Bioavailability/master/FAO_micro_setup.R"
# source_url(SourceURL)
rm(mirdat)

# Labels ... insert the relevant label
str(fao_cal) ## check potential labels
lt <- fao_cal$pB
lv <- fao_val$pB

# Soil spectral features
mirt <- fao_cal[43:1806] # soil MIR
mirv <- fao_val[43:1806] # soil MIR

# RF models ---------------------------------------------------------------
library(doParallel)
library(randomForest)

# Start doParallel to parallelize model fitting
mc <- makeCluster(detectCores())
registerDoParallel(mc)

# Control setup
set.seed(1385321)
tc <- trainControl(method = "cv", allowParallel = T)

# Tuning parameters
tg <- expand.grid(mtry=seq(10, 150, by=10))

# Fit model
mir.rfo <- train(mirt, lt,
                 preProc = c("center", "scale"),
                 method = "rf",
                 ntree = 501,
                 tuneGrid = tg,
                 trControl = tc)
print(mir.rfo)
rfo_mir <- predict(mir.rfo, mirv) ## predict validation set
rm("mir.rfo")

stopCluster(mc)
detach("package:randomForest", unload=TRUE)

# GBM models --------------------------------------------------------------
library(plyr)
library(gbm)

# Start doParallel to parallelize model fitting
mc <- makeCluster(detectCores())
registerDoParallel(mc)

# Control setup
set.seed(1385321)
tc <- trainControl(method = "repeatedcv", repeats=5, allowParallel = T)

# Tuning parameters
tg <- expand.grid(.n.trees=seq(10, 200, by=10), 
                  .interaction.depth = 10,
                  .shrinkage = 0.1,
                  .n.minobsinnode = 10)

# Fit model
mir.gbm <- train(mirt, lt, 
                 method = "gbm",
                 trControl = tc,
                 tuneGrid = tg)
print(mir.gbm)
gbm_mir <- predict(mir.gbm, mirv) ## predict validation set
rm("mir.gbm")

stopCluster(mc)
detach("package:gbm", unload=TRUE)

# PLS models --------------------------------------------------------------
library(pls)

# Start doParallel to parallelize model fitting
mc <- makeCluster(detectCores())
registerDoParallel(mc)

# Control setup
set.seed(1385321)
tc <- trainControl(method = "repeatedcv", repeats = 5, allowParallel = TRUE)

# Fit models
mir.pls <- train(mirt, lt,
                 preProc = c("center", "scale"),
                 method = "pls",
                 tuneGrid = expand.grid(ncomp=seq(2, 20, by=1)),
                 trControl = tc)
print(mir.pls)
pls_mir <- predict(mir.pls, mirv) ## predict validation set
rm("mir.pls")

stopCluster(mc)
detach("package:pls", unload=TRUE)

# bartMachine models ------------------------------------------------------
options(java.parameters = "-Xmx8000m")
library(bartMachine)

# Start doParallel to parallelize model fitting
mc <- makeCluster(detectCores())
registerDoParallel(mc)

# Control setup
tc <- trainControl(method = "cv", returnResamp = "all", allowParallel = T)

# Fit model
mir.bar <- train(mirt, lt,
                 method = "bartMachine", 
                 preProc = c("center", "scale"),
                 trControl = tc,
                 tuneLength = 2,
                 seed = 123)
print(mir.bar)
bar_mir <- predict(mir.bar, mirv)
rm("mir.bar")

stopCluster(mc)
detach("package:bartMachine", unload=TRUE)

# Model stacking setup ----------------------------------------------------
pmirv <- as.data.frame(cbind(lv, rfo_mir, gbm_mir, pls_mir, bar_mir))
names(pmirv) <- c("L", "RFO", "GBM", "PLS", "BART")

# Remove extraneous objects from memory -----------------------------------
# rm(list=setdiff(ls(), pmirv"))

# Model stacking ----------------------------------------------------------
library(glmnet)

# Start doParallel to parallelize model fitting
mc <- makeCluster(detectCores())
registerDoParallel(mc)

# Control setup
set.seed(1385321)
tc <- trainControl(method = "cv", allowParallel = T)

# MIR model stack
set.seed(1385321)
mir.ens <- train(L ~ ., data = pmirv,
                 method = "glmnet",
                 family = "gaussian",
                 trControl = tc)
print(mir.ens)
ens_mir <- as.data.frame(predict(mir.ens, pmirv))
names(ens_mir) <- c("ENS")
pmirv <- cbind(pmirv, ens_mir)

stopCluster(mc)

# Write data files --------------------------------------------------------
write.csv(pmirv, "B_pmirv.csv", row.names=F)

# Prediction plots --------------------------------------------------------
par(mfrow=c(2,2), mar=c(5,4.5,1,1))

# MIR predictions # note that x & y axis limits will need to be adjusted
lmin <- 0
lmax <- max(pmirv$L)
plot(L ~ RFO, pmirv, xlim=c(lmin, lmax), ylim=c(lmin, lmax), xlab = "RFO prediction", ylab = "Observed", cex.lab=1.3)
abline(c(0,1), col="red")
plot(L ~ GBM, pmirv, xlim=c(lmin, lmax), ylim=c(lmin, lmax), xlab = "GBM prediction", ylab = "Observed", cex.lab=1.3)
abline(c(0,1), col="red")
plot(L ~ PLS, pmirv, xlim=c(lmin, lmax), ylim=c(lmin, lmax), xlab = "PLS prediction", ylab = "Observed", cex.lab=1.3)
abline(c(0,1), col="red")
plot(L ~ BART, pmirv, xlim=c(lmin, lmax), ylim=c(lmin, lmax), xlab = "BART prediction", ylab = "Observed", cex.lab=1.3)
abline(c(0,1), col="red")
dev.off()

# Ensemble predictions 
plot(L ~ ENS, pmirv, xlim=c(lmin, lmax), ylim=c(lmin, lmax), xlab = "Model ensemble prediction", ylab = "Observed", cex.lab=1.3)
abline(c(0,1), col="red")