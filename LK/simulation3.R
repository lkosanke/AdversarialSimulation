# Script for Simulation Study 3

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


# Specify 2-factor-Model


model <- "

#Structural part
    FX =~ l1*X1 + l2*X2 + l3*X3
    FY =~ l4*Y1 + l5*Y2 + l6*Y3
    FX ~~ 1*FX    #Fixed latent variance
    FY ~~ 1*FY    #Fixed latent variance
    FX ~~ phi*FY
    phi < 0.99    #Phi between -1 and 1
    phi > -0.99

#Measurement part    
    X1 ~~ vX1*X1
    X2 ~~ vX2*X2    
    X3 ~~ vX3*X3
    Y1 ~~ vY1*Y1
    Y2 ~~ vY2*Y2    
    Y3 ~~ vY3*Y3
    l1 > 0.01     #only positive loadings
    l2 > 0.01    
    l3 > 0.01
    l4 > 0.01
    l5 > 0.01
    l6 > 0.01       
    vX1 > 0.01    #only positive variances
    vX2 > 0.01    
    vX3 > 0.01
    vY1 > 0.01
    vY2 > 0.01    
    vY3 > 0.01   
    "


# Setup and Design

setup_design <- function() {
  # Sample sizes
  N_sizes <- c(50, 100, 250, 500, 1000, 2500, 10^5)
  
  design <- data.frame(N = N_sizes)
  
  return(design)
}




# Data generating Mechanism

## Fixed values

lam1 <- 0.55
lam2 <- 0.45
phi <- 0.60 

# Base loading matrix for two factors
LAM <- matrix(0, nrow=6, ncol=2)
LAM[1:3, 1] <- lam1  
LAM[4:6, 2] <- lam2 

LAM[1, 2] <- 0.3  # Cross-loading deltax1

# Base correlation matrix for factors
PHI <- matrix(0, nrow=2, ncol=2)
diag(PHI) <- 1
PHI[1, 2] <- PHI[2, 1] <- phi

# Base unique variances for observed variables
THETA <- diag(c(rep(1 - lam1^2, 3), rep(1 - lam2^2, 3)))

THETA[2, 5] <- THETA[5, 2] <- 0.12  # Correlated residuals for X2 and Y2



## Varying values

### None

# Apply Syntax


pop.model <- paste(
  
"#Structural part",
    paste("FX =~", LAM[1,1], "*X1 +", LAM[2,1], "*X2 +", LAM[3,1], "*X3"),
    paste("FY =~", LAM[4,2], "*Y1 +", LAM[5,2], "*Y2 +", LAM[6,2], "*Y3 +", LAM[1, 2], "*X1"), # Cross-loading
    "FX ~~ 1*FX",    
    "FY ~~ 1*FY",    
    paste("FX ~~", PHI[1,2], "*FY"),
"#Measurement part",    
    paste("X1 ~~", THETA[1,1], "*X1"),
    paste("X2 ~~", THETA[2,2], "*X2"),
    paste("X3 ~~", THETA[3,3], "*X3"),
    paste("Y1 ~~", THETA[4,4], "*Y1"),
    paste("Y2 ~~", THETA[5,5], "*Y2"),
    paste("Y3 ~~", THETA[6,6], "*Y3"),
"Correlated residual",
    paste("X2 ~~", THETA[2,5], "*Y2"),
    sep = "\n"
  ) 

  



# Simulate data


simulate_data <- function(N) {
  
  df_dat <- simulateData(pop.model, sample.nobs = N)
  
  return(df_dat)
}




# Planned Analysis


#Specify estimation methods of interest

estimators <- list(
  SEM_ML = \(d) lavaan::sem(model, data=d, estimator="ML", std.lv= TRUE),
  SEM_ULS = \(d) lavaan::sem(model, data=d, estimator="ULS", std.lv= TRUE),
  LSAM_ML = \(d) lavaan::sam(model, data=d, sam.method="local", estimator = "ML", std.lv= TRUE),
  LSAM_ULS = \(d)lavaan::sam(model, data=d, sam.method="local", estimator = "ULS", std.lv= TRUE),
  GSAM_ML = \(d) lavaan::sam(model, data=d, sam.method = "global", estimator = "ML", std.lv= TRUE),
  GSAM_ULS = \(d) lavaan::sam(model, data=d, sam.method = "global", estimator = "ULS", std.lv= TRUE)
)
# postprocess each model output
estimators <- modify(estimators, ~compose(\(e)filter(e, label == "phi")$est, parameterEstimates, .))
# apply all estimators to the same dataset
apply_estimators <- \(d) map(estimators, exec, d)

planned_analysis <- compose(apply_estimators, simulate_data)

#Args of planned_analysis() = Args of simulate_data()


# Extract results


extract_results <- function(results_df_raw){
#Compute performance measures
results_metrics <- results_df_raw %>%
    group_by(N) %>%
    summarize(across(everything(),
       list(
          abs_bias = ~mean(abs(.x - phi)),              # Average absolute bias
          rel_bias = ~mean(.x - phi) / phi,             # Relative bias
          sd = ~sd(.x),                                 # Standard deviation of estimates
          rmse = ~sqrt(mean((.x - phi)^2)),             # Root mean square error
          se_bias = ~(sd(abs(.x - phi)))/ sqrt(unique(N)),      # SE of bias
          ci_lower = ~((mean(.x - phi) / phi) - qt(0.975, df = unique(N) - 1) * (sd(abs(.x - phi)))/ sqrt(unique(N))),  # Lower CI for relative Bias
          ci_upper = ~((mean(.x - phi) / phi) + qt(0.975, df = unique(N) - 1) * (sd(abs(.x - phi)))/ sqrt(unique(N)))   # Upper CI for relative Bias
                    )),  .groups = 'drop')


  # transform each group into the desired format
  transform_group <- results_metrics %>%
      pivot_longer(cols = starts_with(c("SEM_","LSAM_","GSAM_")), values_to = "value")

    # Creating nested lists for each metric
  metrics_list <-  list(
                          abs_bias = transform_group %>% filter(str_detect(name, "abs_bias")) %>%
                                     pivot_wider(names_from = N, values_from = value),
                          rel_bias = transform_group %>% filter(str_detect(name, "rel_bias")) %>%
                                     pivot_wider(names_from = N, values_from = value),
                          sd = transform_group %>% filter(str_detect(name, "sd")) %>%
                                  pivot_wider(names_from = N, values_from = value),
                          rmse = transform_group %>% filter(str_detect(name, "rmse")) %>%
                                  pivot_wider(names_from = N, values_from = value),
                          se_bias = transform_group %>% filter(str_detect(name, "se_bias")) %>%
                                    pivot_wider(names_from = N, values_from = value),
                          ci_lower = transform_group %>% filter(str_detect(name, "ci_lower")) %>%
                                    pivot_wider(names_from = N, values_from = value),
                          ci_upper = transform_group %>% filter(str_detect(name, "ci_upper")) %>%
                                    pivot_wider(names_from = N, values_from = value)
                        )

  return(metrics_list)
}


# Report bias


report_bias <- function(metrics_list) {
  # Define a list to store results
  bias_ci <- list()
  
  # Iterate over each condition in metrics_list
    # Extract rel_bias, ci_lower, and ci_upper for the current condition
    rel_bias <- metrics_list$rel_bias
    ci_lower <- metrics_list$ci_lower
    ci_upper <- metrics_list$ci_upper
    
    # Create the bias_ci table for the current condition and store it in the list
    bias_ci <- rel_bias %>%
      mutate(across(`50`:`1e+05`, ~pmap_chr(list(rel_bias[[cur_column()]], ci_lower[[cur_column()]], ci_upper[[cur_column()]]),
                                            ~sprintf("%.3f [%.3f-%.3f]", ..1, ..2, ..3)),
             .names = "{.col}"))
  
  return(bias_ci)
}


# Report SD


report_sd <- function(metrics_list) {
  # Use map to extract the sd data from each element in the metrics_list
  sd <- map(metrics_list, ~ {
    .x$sd  # Extract and return the sd component
  })

  return(sd)  # Return the list of sd data frames
}


# Report RMSE


report_rmse <- function(metrics_list) {
  # Use map to extract the rmse data from each element in the metrics_list
  rmse <- map(metrics_list, ~ {
    .x$rmse  # Extract and return the rmse component
  })

  return(rmse)  # Return the list of rmse data frames
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


### Set up design
design <- setup_design()

### Run simulation
results_sim <- simulation_study(design, 1500, seed = TRUE)
saveRDS(results_sim, file = "sim3_results_error.rds")

### Errors, warnings and messages?
errors <- results_sim$errors
warnings <- results_sim$warnings
messages <- results_sim$messages

### Output and extract results
results_df_raw <- results_sim$results
saveRDS(results_df_raw, file = "sim3_results_raw.rds")

metrics_list <- extract_results(results_df_raw)
saveRDS(metrics_list, file = "sim3_metrics_list.rds")

### Report Bias
bias_ci <- report_bias(metrics_list)
saveRDS(bias_ci, file = "sim3_rel_bias_ci.rds")

### Report SD
sd <- report_sd(metrics_list)
saveRDS(sd, file = "sim3_sd.rds")

### Report RMSE
rmse <- report_rmse(metrics_list)
saveRDS(rmse, file = "sim3_rmse.rds")


