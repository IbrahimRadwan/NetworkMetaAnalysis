par.defaults <- par(no.readonly = TRUE)
save(par.defaults, file="R.default.par.RData")
load("R.default.par.RData")

library(R2jags)
library(abind)
library(boot)
library(ggplot2)

#
# load data, create data frame ------------------------------------------------
#
# extract all .csv files that contain RY and SE
# create list of data frames
setwd("/Users/nicolekinlock/Documents/Plant Ecology/NetworkMetaAnalysis/Networks/Biomass/MixMono")
files <- dir(pattern = "*.csv", full.names = TRUE)
tables <- lapply(files, function(x) read.csv(x))
indices <- sapply(tables, function(x) any(colnames(x) == "SE"))
tables <- tables[indices]  # subset by only studies with SE
tables.metric <- lapply(tables, `[`, 3)
tables.SE <- lapply(tables, `[`, c(4, 5))
tables.SD <- lapply(tables.SE, function(x) sqrt(x[, 2]) * x[, 1])
metric <- unlist(lapply(tables.metric, function(x) as.vector(t(x))))
SD <- unlist(lapply(tables.SD, function(x) as.vector(t(x))))
dat <- data.frame(Metric = metric, SD = SD)

# extract files with missing SE
# add to data frame for prediction
setwd("/Users/nicolekinlock/Documents/Plant Ecology/NetworkMetaAnalysis/Networks/Biomass/Cntrl/Impute/")
files.missing <- dir(pattern = "*.csv", full.names = TRUE)
tables.missing <- lapply(files.missing, function(x) read.csv(x))
missing <- unlist(lapply(tables.missing, function(x) x$Metric))
missing.SD <- rep(NA, length(missing))
newrows <- cbind(Metric = missing, SD = missing.SD)
dat <- rbind(dat, newrows)

#
# write statistical model code to a text file ------------------------------------------------
#

sink("imputeBiomassCntrl.jags")

cat("
    model {
    for (i in 1:length(y)) {
    y[i] ~ dgamma(alpha, alpha / exp(theta[i]))
    predicted_obs[i] ~ dgamma(alpha, alpha / exp(theta[i]))
    theta[i] <- beta0 + beta1 * metric[i]
    }
    beta0 ~ dnorm(0, 1.0E-6)
    beta1 ~ dnorm(0, 1.0E-6)
    alpha ~ dunif(0, 100)
    }", fill = TRUE)

sink()

#
# create list with data model needs to run ------------------------------------------------
#

Dat <- list(
  y = dat[, 2],
  metric = dat[, 1]
)

#
# make function with list of parameters and initial values ------------------------------------------------
#

InitStage <- function() {
  list(beta0 = 0.5, beta1 = 1, alpha = 2)
}

#
# make column vector with the parameters to track ------------------------------------------------
#

ParsStage <- c("beta0", "beta1", "alpha", "theta", "predicted_obs")

#
# set the variables for MCMC ------------------------------------------------
#

ni <- 10000  # number of draws from the posterior
nt <- 1    # thinning rate
nb <- 1000  # number to discard for burn-in
nc <- 2  # number of chains

#
# call jags function to run the code ------------------------------------------------
#

m <- jags(inits = InitStage,
          n.chains = nc,
          model.file = "imputeBiomassCntrl.jags",
          working.directory = getwd(),
          data = Dat,
          parameters.to.save = ParsStage,
          n.thin = nt,
          n.iter = ni,
          n.burnin = nb,
          DIC = TRUE)

#
# print summary ------------------------------------------------
#

m

dim(m$BUGSoutput$sims.array)
dim(m$BUGSoutput$sims.matrix)

#
# plot results ------------------------------------------------
#

# for alpha
par(mfrow = c(2, 2), mar = c(4, 4, 2, 0.4))
beta1.chain.1 <- as.mcmc(m$BUGSoutput$sims.array[nb: length(m$BUGSoutput$sims.array[, 1, 1]), 1, 1])
beta1.chain.2 <- as.mcmc(m$BUGSoutput$sims.array[nb: length(m$BUGSoutput$sims.array[, 2, 1]), 2, 1])
densplot(beta1.chain.1, main = "Chain 1", xlab = "")
densplot(beta1.chain.2, main = "Chain 2", xlab = "")
traceplot(beta1.chain.1, xlab = "alpha" )
traceplot(beta1.chain.2, xlab = "alpha")

# for beta0
beta1.chain.1 <- as.mcmc(m$BUGSoutput$sims.array[nb: length(m$BUGSoutput$sims.array[, 1, 2]), 1, 2])
beta1.chain.2 <- as.mcmc(m$BUGSoutput$sims.array[nb: length(m$BUGSoutput$sims.array[, 2, 2]), 2, 2])
densplot(beta1.chain.1, main = "Chain 1", xlab = "")
densplot(beta1.chain.2, main = "Chain 2", xlab = "")
traceplot(beta1.chain.1, xlab = "beta0" )
traceplot(beta1.chain.2, xlab = "beta0")

# for beta1
beta1.chain.1 <- as.mcmc(m$BUGSoutput$sims.array[nb: length(m$BUGSoutput$sims.array[, 1, 3]), 1, 3])
beta1.chain.2 <- as.mcmc(m$BUGSoutput$sims.array[nb: length(m$BUGSoutput$sims.array[, 2, 3]), 2, 3])
densplot(beta1.chain.1, main = "Chain 1", xlab = "")
densplot(beta1.chain.2, main = "Chain 2", xlab = "")
traceplot(beta1.chain.1, xlab = "beta1" )
traceplot(beta1.chain.2, xlab = "beta1")

theta <- grep("theta", row.names(m$BUGSoutput$summary))
predicted_obs <- grep("predicted_obs", row.names(m$BUGSoutput$summary))
CI.95.low <- m$BUGSoutput$summary[theta, 3]  # 95% CIs for every theta
CI.95.high <- m$BUGSoutput$summary[theta, 7]
PI.95.low <- m$BUGSoutput$summary[predicted_obs, 3]  # 95% PIs for every predicted obs.
PI.95.high <- m$BUGSoutput$summary[predicted_obs, 7]
theta.mean <- m$BUGSoutput$summary[theta, 1]  # mean for every theta (linear predictor)

dat.output <- data.frame(dat, theta = theta.mean, CI.l = CI.95.low, CI.h = CI.95.high, PI.l = PI.95.low, PI.h = PI.95.high)

missing <- which(is.na(dat$SD))
impute <- c()
for (i in missing) {
  a <- sample(m$BUGSoutput$sims.matrix[, i], size = 1)
  impute <- c(impute, a)
}

dat.output[missing, 2] <- impute

ggplot(data = dat.output) + geom_point(aes(x = Metric, y = SD)) + geom_line(aes(x = Metric, y = exp(theta))) +
  geom_line(aes(x = Metric, y = exp(CI.l)), linetype = "dashed", colour = "seagreen4") + 
  geom_line(aes(x = Metric, y = exp(CI.h)), linetype = "dashed", colour = "seagreen4") +
  geom_line(aes(x = Metric, y = PI.l), linetype = "dotted", colour = "dodgerblue1") + 
  geom_line(aes(x = Metric, y = PI.h), linetype = "dotted", colour = "dodgerblue1") +
  coord_cartesian(xlim = c(0, 20), ylim = c(0, 20)) + ylab("SD") + xlab("Metric") + ggtitle("Imputing SD") + theme_bw()

#
# save imputed SEs to file ------------------------------------------------
#

imputed <- dat.output[missing, 2]
rows <- unlist(lapply(tables.missing, nrow))
chunks <- rep(seq_along(rows), times = rows)
toreplace <- split(imputed, chunks)

for (h in 1:length(tables.missing)) {
  tables.missing[[h]][, 4] <- toreplace[[h]]
  colnames(tables.missing[[h]])[4] <- "SD"
  write.table(x = tables.missing[[h]], file = paste("/Users/nicolekinlock/Documents/Plant Ecology/NetworkMetaAnalysis/Networks/Biomass/Cntrl/", substr(files.missing[h], 3, nchar(files.missing[h]) - 4), "-imp.csv", sep = ""), sep = ",", row.names = FALSE) 
}




