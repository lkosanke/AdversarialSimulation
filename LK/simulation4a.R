# First script for Simulation Study 4a

set.seed(1)


# Packages

## Specify the libraries to load
libraries <- c("lavaan", "purrr", "tidyverse", "furrr")
## Set the R mirror to the cloud mirror of RStudio
options(repos = "https://cloud.r-project.org/")

## Load the libraries
for (library_name in libraries) {
  if (!require(library_name, character.only = TRUE)) {
    install.packages(library_name)
    library(library_name, character.only = TRUE)
  }
}



# Specify 5-factor-Model

model <- "

#Structural part
    F1 =~ l1*y1 + l2*y2 + l3*y3
    F2 =~ l4*y4 + l5*y5 + l6*y6
    F3 =~ l7*y7 + l8*y8 + l9*y9
    F4 =~ l10*y10 + l11*y11 + l12*y12
    F5 =~ l13*y13 + l14*y14 + l15*y15
    
#Fixed latent variances    
    F1 ~~ 1*F1    
    F2 ~~ 1*F2
    F3 ~~ 1*F3
    F4 ~~ 1*F4
    F5 ~~ 1*F5
    
#Regressions
    F3 ~ phi31*F1
    F4 ~ phi41*F1
    F5 ~ phi51*F1
    F3 ~ phi32*F2
    F4 ~ phi42*F2
    F5 ~ phi53*F3
    F3 ~ phi43*F4
    F5 ~ phi54*F4

#Measurement part    
    y1 ~~ vY1*y1
    y2 ~~ vY2*y2    
    y3 ~~ vY3*y3
    y4 ~~ vY4*y4
    y5 ~~ vY5*y5    
    y6 ~~ vY6*y6
    y7 ~~ vY7*y7
    y8 ~~ vY8*y8
    y9 ~~ vY9*y9
    y10 ~~ vY10*y10
    y11 ~~ vY11*y11
    y12 ~~ vY12*y12
    y13 ~~ vY13*y13
    y14 ~~ vY14*y14
    y15 ~~ vY15*y15

#only positive loadings    
    l1 > 0.01          
    l2 > 0.01    
    l3 > 0.01
    l4 > 0.01
    l5 > 0.01
    l6 > 0.01
    l7 > 0.01
    l8 > 0.01
    l9 > 0.01
    l10 > 0.01
    l11 > 0.01
    l12 > 0.01
    l13 > 0.01
    l14 > 0.01
    l15 > 0.01
    
#only positive variances    
    vY1 > 0.01    
    vY2 > 0.01    
    vY3 > 0.01
    vY4 > 0.01
    vY5 > 0.01    
    vY6 > 0.01
    vY7 > 0.01
    vY8 > 0.01
    vY9 > 0.01
    vY10 > 0.01
    vY11 > 0.01
    vY12 > 0.01
    vY13 > 0.01
    vY14 > 0.01
    vY15 > 0.01
    
    "


# Setup and Design

setup_design <- function() {
  
  # Sample sizes
  N_sizes <- c(50, 100, 250, 500, 1000, 2500, 10^5)
  
  # DGM conditions, numbering analogous to paper by Rosseel and Loh for later functions
  DGM_types <- c(1,2)
  
  #beta conditions
  beta_sizes <- c(0.1,0.2,0.3,0.4)
  
  # Expand grid to create a data frame of all combinations
  design <- expand.grid(N = N_sizes, DGM = DGM_types, beta = beta_sizes)


  return(design)
}


# Data generating Mechanism

### This time, we will define the DGM the same way Rosseel and Loh did here: https://osf.io/96zhs

get_dgm <- lav_sam_gen_model <- function(nfactors = 3L, nvar.factor = 3L,
                              lambda = 0.70, PSI = NULL, BETA = NULL,
                              psi.cor = 0.3, reliability = 0.80, 
                              misspecification = 0L, rho=0.80) {

    # 1. LAMBDA
    fac <- matrix(c(1, rep(lambda, times = (nvar.factor - 1L))),
                   nvar.factor, 1L)
    LAMBDA <- lav_matrix_bdiag(rep(list(fac), nfactors))
    
    if (misspecification==1L) {
        # misspecification in the measurement part: cross-loadings
        i.cross <- (0:(nfactors-1))*nvar.factor+ceiling(nvar.factor/2)
        for (j in 1:ncol(LAMBDA)) {
            LAMBDA[i.cross[j],c(2:nfactors,1)[j]] <- rho*lambda
        }
    }
    
    # 2. PSI (in correlation metric)
    if(!is.null(PSI)) {
        stopifnot(nrow(PSI) == ncol(LAMBDA),
                  all((t(PSI) - PSI) == 0))
        if(!is.null(BETA)) {
            stopifnot(nrow(BETA) == ncol(LAMBDA),
                      all(diag(BETA) == 0))
            IB.inv <- solve(diag(nrow(BETA)) - BETA)
            VETA <- IB.inv %*% PSI %*% t(IB.inv)
        } else {
            VETA <- PSI
        }
    } else {
        PSI.cor <- matrix(psi.cor, nfactors, nfactors)
        diag(PSI.cor) <- 1L
        # convert to covariance matrix (not yet for now)
        PSI <- PSI.cor
        BETA <- NULL
        VETA <- PSI
    }

    # 3. THETA (depending on PSI, LAMBDA, and the required reliability)
    tmp <- diag(LAMBDA %*% VETA %*% t(LAMBDA))
    theta.diag <- tmp/reliability - tmp
    # no zero or negative theta values on the diagonal
    stopifnot(all(theta.diag > 0))
    THETA <- matrix(0, nrow(LAMBDA), nrow(LAMBDA))
    diag(THETA) <- theta.diag
    
    if (misspecification==2L) {
        # misspecification in the measurement part: 
        ## missing correlated indicator residuals
        i1.corr <- (0:(nfactors-1))*nvar.factor+ceiling(nvar.factor/2)
        i2.corr <- (1:nfactors)*nvar.factor
        for (t.i in 1:(nfactors-1)) {
            for (t.j in (t.i+1):nfactors) {
                # upper diagonal entries
                THETA[i1.corr[t.i],i1.corr[t.j]] <- min(diag(THETA))*rho
                THETA[i2.corr[t.i],i2.corr[t.j]] <- min(diag(THETA))*rho
            }
        }
        # return symmetric matrix
        THETA[lower.tri(THETA)] <- t(THETA)[lower.tri(THETA)]
    }

    if(is.null(BETA)) {
        MLIST <- list(lambda = LAMBDA, theta = THETA, psi = PSI)
    } else {
        MLIST <- list(lambda = LAMBDA, theta = THETA, psi = PSI, beta = BETA)
    }

    MLIST
}



# Generate Syntax for Data simulation

### Function taken from RL: https://osf.io/4we3h

apply_syntax <-lav_syntax_mlist <- function(MLIST, ov.prefix = "y", lv.prefix = "f",
                             include.values = TRUE) {
    
    # model matrices
    LAMBDA <- MLIST$lambda
    THETA  <- MLIST$theta
    PSI    <- MLIST$psi
    BETA   <- MLIST$beta

    # check prefix
    if(ov.prefix == lv.prefix) {
        stop("lavaan ERROR: ov.prefix can not be the same as lv.prefix")
    }

    header <- "# syntax generated by lav_syntax_mlist()"

    # LAMBDA
    if(!is.null(LAMBDA)) {
        IDXV <- row(LAMBDA)[(LAMBDA != 0)]
        IDXF <- col(LAMBDA)[(LAMBDA != 0)]
        # lambda.txt <- character(nfactors)
        # for(f in seq_len(nfactors)) {
        #      var.idx <- which(LAMBDA[,f] != 0.0)
        #      lambda.vals <- LAMBDA[var.idx, f]
        #      lambda.txt[f] <- paste( paste0(lv.prefix, f), "=~",
        #                              paste(lambda.vals, "*", 
        #                              paste0(ov.prefix, var.idx), 
        #                              sep = "", collapse = " + ") ) 
        # }
        
        # reorder indicators to satisfy unit factor loading
        IDXV <- as.integer(sapply(unique(IDXF), function(j) {
          ji <- IDXV[which(IDXF==j)] # non-zero loadings for factor j
          # fix first factor with unit factor loading
          j1 <- which(abs(LAMBDA[ji,j]-1)<.Machine$double.eps)
          ji[c(1,j1)] <- ji[c(j1,1)]
          return(ji)
        }))
        
        nel <- length(IDXF)
        lambda.txt <- character(nel)
        for(i in seq_len(nel)) {
            if(include.values) {
                lambda.txt[i] <- paste0(paste0(lv.prefix, IDXF[i]), " =~ ",
                                        LAMBDA[IDXV[i],IDXF[i]], "*",
                                        paste0(ov.prefix, IDXV[i]))
            } else {
                lambda.txt[i] <- paste0(paste0(lv.prefix, IDXF[i]), " =~ ",
                                        paste0(ov.prefix, IDXV[i]))
            }
        }
    } else {
        lambda.txt <- character(0L)
    }

    # THETA
    if(!is.null(THETA)) {
        IDX1 <- row(THETA)[(THETA != 0) & upper.tri(THETA, diag = TRUE)]
        IDX2 <- col(THETA)[(THETA != 0) & upper.tri(THETA, diag = TRUE)]
        nel <- length(IDX1)
        theta.txt <- character(nel)
        for(i in seq_len(nel)) {
            if(include.values) {
                theta.txt[i] <- paste0(paste0(ov.prefix, IDX1[i]), " ~~ ",
                                       THETA[IDX1[i], IDX2[i]], "*",
                                       paste0(ov.prefix, IDX2[i]))
            } else {
                theta.txt[i] <- paste0(paste0(ov.prefix, IDX1[i]), " ~~ ",
                                       paste0(ov.prefix, IDX2[i]))
            }
        }
    } else {
        theta.txt <- character(0L)
    }

    # PSI
    if(!is.null(PSI)) {
        IDX1 <- row(PSI)[(PSI != 0) & upper.tri(PSI, diag = TRUE)]
        IDX2 <- col(PSI)[(PSI != 0) & upper.tri(PSI, diag = TRUE)]
        nel <- length(IDX1)
        psi.txt <- character(nel)
        for(i in seq_len(nel)) {
            if(include.values) {
                psi.txt[i] <- paste0(paste0(lv.prefix, IDX1[i]), " ~~ ",
                                     PSI[IDX1[i],IDX2[i]], "*",
                                     paste0(lv.prefix, IDX2[i]))
            } else {
                psi.txt[i] <- paste0(paste0(lv.prefix, IDX1[i]), " ~~ ",
                                     paste0(lv.prefix, IDX2[i]))
            }
        }
    } else {
        psi.txt <- character(0L)
    }

    # BETA
    if(!is.null(BETA)) {
        IDX1 <- row(BETA)[(BETA != 0)]
        IDX2 <- col(BETA)[(BETA != 0)]
        nel <- length(IDX1)
        beta.txt <- character(nel)
        for(i in seq_len(nel)) {
            if(include.values) {
                beta.txt[i] <- paste0(paste0(lv.prefix, IDX1[i]), " ~ ",
                                      BETA[IDX1[i],IDX2[i]], "*",
                                      paste0(lv.prefix, IDX2[i]))
            } else {
                beta.txt[i] <- paste0(paste0(lv.prefix, IDX1[i]), " ~ ",
                                      paste0(lv.prefix, IDX2[i]))
            }
        }
    } else {
        beta.txt <- character(0L)
    }

    # assemble
    syntax <- paste(c(header, lambda.txt, theta.txt, psi.txt, beta.txt, ""),
                        collapse = "\n")
    
    syntax
}
  

# Simulate data
### Analogously to Rosseel and Loh, we will simulate the data with the lavaan function, for each condition.

simulate_data <- function(N, DGM, beta) {
 NFAC   <- 5L    # number of factors
  FVAR   <- 3L    # number of indicators per factor
  lambda <- 0.70  # lambda value
  # reliability for all indicators
  REL    <- 0.7
  # same beta value for all regression coefficients
  
  # f1 -> f3, f4, f5
  # f2 -> f3, f4
  # f3 -> f5
  # f4 -> f3, f5
  # var(f1) == var(f2) == 1
  
  BETA <- matrix(0, NFAC, NFAC)
  BETA[3:5,1] <- BETA[3:4,2] <- BETA[5,3] <- BETA[c(3,5),4] <- beta
  VAL <- BETA[BETA!=0] # true values
  BETA.model <- BETA   # structural part to be fitted
  
  PSI <- matrix(0, NFAC, NFAC)
  PSI[1,1] <- PSI[2,2] <- 1 # the exogenous latent variables
  RES <- (1 - beta^2)
  PSI[lav_matrix_diag_idx(NFAC)[-c(1:2)]] <- RES
  
  #need: assumed_model=c(1:2)
  #need: true_model=c(1:2)
  #But both seperately. Here, starting with 1
  assumed_model= DGM
  true_model= DGM
  
  
  # generate pop model matrices
  MLIST <- lav_sam_gen_model(nfactors = NFAC, nvar.factor = FVAR, lambda = lambda,
                             PSI = PSI, BETA = BETA, reliability = REL, 
                             misspecification = true_model,
                             rho = ifelse(true_model==2L,0.6,0.9))
  
  # Specify population model
  
  pop.model <- lav_syntax_mlist(MLIST, include.values = TRUE)

  #Simulate Data
  df_dat <- simulateData(pop.model, sample.nobs = N)

  return(df_dat)
}






# Planned Analysis

## Specify estimation methods of interest

estimators <- list(
  SEM_ML = \(d) lavaan::sem(model, data=d, estimator="ML", std.lv= TRUE),
  SEM_ULS = \(d) lavaan::sem(model, data=d, estimator="ULS", std.lv= TRUE),
  LSAM_ML = \(d) lavaan::sam(model, data=d, sam.method="local", estimator = "ML", std.lv= TRUE)
)
## postprocess each model output
phi_patterns <- c("phi31", "phi41", "phi51", "phi32", "phi42", "phi43", "phi53", "phi54")

estimators <- map(estimators, ~compose(
  \(e) parameterEstimates(e) %>% filter(label %in% phi_patterns) %>% pull(est), 
  .
))

## apply all estimators to the same dataset
apply_estimators <- \(d) map(estimators, exec, d)

planned_analysis <- function(N, DGM, beta){
  d <- simulate_data(N,DGM, beta)
  results <- apply_estimators(d)
  
  return(tibble(
    SEM_ML = list(results$SEM_ML),
    SEM_ULS = list(results$SEM_ULS),
    LSAM_ML = list(results$LSAM_ML)
  ))
}
#The arguments to planned_analysis() are always equivalent to the ones from simulate_data(), within one simulation


# Extract results

extract_results <- function(results_df_raw) {
    
  results_raw_combined <- results_df_raw %>%
    group_by(N, DGM, beta) %>%
    summarise(across(c(SEM_ML, SEM_ULS, LSAM_ML), 
                     ~list(unlist(.))), 
              .groups = "drop")
  
  # Compute performance measures for each estimator
  results_metrics <- function(values, beta) {
    list(
      abs_bias = mean(abs(values - beta)),  
      rel_bias = mean(values - beta) / beta,
      rmse = sqrt(mean(values - beta^2)),
      se_bias = sd(values - beta) / sqrt(length(values)),
      ci_lower = mean(values - beta) - qt(0.975, df = length(values) - 1) * sd(values - beta) / sqrt(length(values)),
      ci_upper = mean(values - beta) + qt(0.975, df = length(values) - 1) * sd(values - beta) / sqrt(length(values))
    )
  }

  # Apply the performance metrics function to each estimator and create metrics columns
  metrics_list <- results_raw_combined %>%
    mutate(across(c(SEM_ML, SEM_ULS, LSAM_ML), 
                  ~map2(.x, beta, results_metrics), .names = "{.col}_metrics")) %>%
    select(-c(SEM_ML, SEM_ULS, LSAM_ML))  # Drop the original estimator columns

  return(metrics_list)
}





# Report Bias

report_bias <- function(metrics_list) {
  # Define the list of estimators
  estimators <- c("SEM_ML_metrics", "SEM_ULS_metrics", "LSAM_ML_metrics")
  
  # Ensure DGM values are uniquely identified
  unique_dgms <- unique(metrics_list$DGM)
  unique_betas <- unique(metrics_list$beta)
  unique_ns <- unique(metrics_list$N)
  
  # Process each DGM
  results_by_dgm <- map(set_names(unique_dgms), ~{
    dgm <- .x
    
    # Create a list to hold results for each estimator
    estimator_results <- map(estimators, function(estimator) {
      
      # Filter data for the current DGM and estimator
      filtered_data <- metrics_list %>% filter(DGM == dgm)
      
      # Create a list to hold results for each beta value
      beta_results <- map(unique_betas, function(beta_val) {
        filtered_beta_data <- filtered_data %>% filter(beta == beta_val)
        
        # Create a list to hold results for each N
        n_results <- map_dfc(unique_ns, function(n_val) {
          metrics <- filtered_beta_data %>% filter(N == n_val) %>% pull(estimator)
          metrics <- metrics[[1]]
          formatted_bias <- sprintf("%.3f [%.3f, %.3f]", metrics$abs_bias, metrics$ci_lower, metrics$ci_upper)
          set_names(formatted_bias, paste("N", n_val, sep = "_"))
        })
        
        tibble(beta = beta_val) %>% bind_cols(n_results)
      })
      
      beta_results <- bind_rows(beta_results)
      set_names(beta_results, c("beta", paste("N", unique_ns, sep = "_")))
    })
    
    set_names(estimator_results, estimators)
  }, .options = furrr_options(seed = TRUE))  # Ensure reproducibility with seeds
  
  # Combine results by DGM and estimator
  results_by_dgm_estimator <- map(unique_dgms, function(dgm) {
    map(estimators, function(estimator) {
      results_by_dgm[[paste(dgm)]][[estimator]]
    })
  })
  
  # Set names for easier access
  names(results_by_dgm_estimator) <- paste("DGM", unique_dgms, sep = "_")
  results_by_dgm_estimator <- map(results_by_dgm_estimator, function(dgm_results) {
    set_names(dgm_results, estimators)
  })
  
  results_by_dgm_estimator
}



# Report RMSE

report_rmse <- function(metrics_list) {
  # Define the list of estimators
  estimators <- c("SEM_ML_metrics", "SEM_ULS_metrics", "LSAM_ML_metrics")
  
  # Ensure DGM values are uniquely identified
  unique_dgms <- unique(metrics_list$DGM)
  unique_betas <- unique(metrics_list$beta)
  unique_ns <- unique(metrics_list$N)
  
  # Process each DGM
  results_by_dgm <- map(set_names(unique_dgms), ~{
    dgm <- .x
    
    # Create a list to hold results for each estimator
    estimator_results <- map(estimators, function(estimator) {
      
      # Filter data for the current DGM and estimator
      filtered_data <- metrics_list %>% filter(DGM == dgm)
      
      # Create a list to hold results for each beta value
      beta_results <- map(unique_betas, function(beta_val) {
        filtered_beta_data <- filtered_data %>% filter(beta == beta_val)
        
        # Create a list to hold results for each N
        n_results <- map_dfc(unique_ns, function(n_val) {
          metrics <- filtered_beta_data %>% filter(N == n_val) %>% pull(estimator)
          metrics <- metrics[[1]]
          formatted_rmse <- sprintf("%.3f", metrics$rmse)
          set_names(formatted_rmse, paste("N", n_val, sep = "_"))
        })
        
        tibble(beta = beta_val) %>% bind_cols(n_results)
      })
      
      beta_results <- bind_rows(beta_results)
      set_names(beta_results, c("beta", paste("N", unique_ns, sep = "_")))
    })
    
    set_names(estimator_results, estimators)
  }, .options = furrr_options(seed = TRUE))  # Ensure reproducibility with seeds
  
  # Combine results by DGM and estimator
  results_by_dgm_estimator <- map(unique_dgms, function(dgm) {
    map(estimators, function(estimator) {
      results_by_dgm[[paste(dgm)]][[estimator]]
    })
  })
  
  # Set names for easier access
  names(results_by_dgm_estimator) <- paste("DGM", unique_dgms, sep = "_")
  results_by_dgm_estimator <- map(results_by_dgm_estimator, function(dgm_results) {
    set_names(dgm_results, estimators)
  })
  
  results_by_dgm_estimator
}




#  Simulation Study

simulation_study_ <- function(design){
  all_steps <- mutate(design, !!!future_pmap_dfr(design, planned_analysis, .options = furrr_options(seed = TRUE)))
  all_steps
}

simulation_study <- function(design, k, seed = NULL) {
  # Define a function to run simulation_study_() safely
  safe_simulation <- function(design) {
    # Run the simulation function safely
    result <- quietly(safely(simulation_study_))(design)
    
    # Extract the output, errors, and warnings: Question: On which level do we want this? Do obtain the correct DF, triple indexing into safely() is  necessary.
    output <- if (!is.null(result$error)) NULL else result$result$result
    errors <- if (!is.null(result$error)) result$error else NULL
    warnings <- if (!is.null(result$warning)) result$warning else NULL
    messages <- result$message
    
    # Return a list with the output, errors, and warnings
    list(result = output, errors = errors, warnings = warnings, messages = messages)
  }
  
  # Run simulation_study_() k times, capturing errors and warnings
  results_list <- future_map(seq_len(k), ~safe_simulation(design), .options = furrr_options(seed = seed))
  
  # Extract result, errors, and warnings from the list
  results <- map_df(results_list, pluck, "result")
  errors <- map(results_list, pluck, "errors")
  warnings <- map(results_list, pluck, "warnings")
  messages <- map(results_list, pluck, "messages")
  
  # Combine results, errors, and warnings into a single data frame

  return(list(results = results, errors = errors, warnings = warnings, messages = messages))
}




# Run & safe simulation

#Set up design
design <- setup_design()

#Run & safe simulation
results_sim <- simulation_study(design, 1500, seed = TRUE)
saveRDS(results_sim, file = "sim4a_results_error.rds")

#Errors, warnings and messages?
errors <- results_sim$errors
warnings <- results_sim$warnings
messages <- results_sim$messages

#Output and extract results
results_df_raw <- results_sim$results
saveRDS(results_df_raw, file = "sim4a_results_raw.rds")

metrics_list <- extract_results(results_df_raw)
saveRDS(metrics_list, file = "sim4a_metrics_list.rds")

#Report Bias
bias_ci <- suppressMessages(report_bias(metrics_list))
saveRDS(bias_ci, file = "sim4a_abs_bias_ci.rds")

#Report RMSE
rmse <- suppressMessages(report_rmse(metrics_list))
saveRDS(rmse, file = "sim4a_rmse.rds")
