library(dplyr)
library(ggplot2)
library(tidyr)
library(patchwork)
library(caret)
library(plotly)

data = read.csv("titanic.csv")

# head(data)
############################################################################################
#  Overview and preparing data
############################################################################################
# tibble(
#   column      = names(data),
#   type        = sapply(data, class),
#   n_unique    = sapply(data, function(x) length(unique(x)))
# ) |> print(n = Inf)
# # we can see there is 891 names, and IDs. So we likely have no duplicates
# 
# lapply(data, function(x) prop.table(table(x)) * 100) # Just to check the general % of each data type


# tibble(
#   column      = names(data),
#   n_NA        = colSums(is.na(data)),
#   n_NaN       = sapply(data, function(x) sum(is.nan(x))),
#   n_Inf       = sapply(data, function(x) sum(is.infinite(x))),
#   n_empty_str = sapply(data, function(x) sum(x == "", na.rm = TRUE)),
#   pct_missing = round(colMeans(is.na(data)) * 100, 1)
# ) |> print(n = Inf)

# here we see Age, Cabin, Embarked are the problematic data columns


# data %>%
#   add_count(Ticket) %>%
#   filter(n > 1) %>%
#   arrange(Ticket)
# # Checking the duplicate ticket rows


# # 1. Create the custom price buckets
# data$FareBucket <- cut(data$Fare, 
#                        breaks = c(-Inf, 3, 8, 15, 30, Inf), 
#                        labels = c("< £3", "£3-8 (3rd Class)", "£8-15 (2nd Class)", "£15-30 (1st Entry)", "> £30 (1st Luxury)"))
# 
# # 2. Build the ggplot
# p <- ggplot(data, aes(x = FareBucket, fill = FareBucket)) +
#   geom_bar(color = "white") +
#   scale_fill_brewer(palette = "Blues") +
#   labs(title = "Titanic Passengers by Ticket Price Category", 
#        x = "Fare Range (£)", 
#        y = "Number of Passengers") +
#   theme_minimal() +
#   theme(legend.position = "none") # Hides legend since labels are on X-axis
# 
# # 3. Make it interactive
# ggplotly(p)
# 
# # 1. Filter for anyone who paid less than 3 pounds
# sub_3_rows <- data %>%
#   filter(Fare < 3)
# 
# # 2. Print the rows to see who they are
# print(sub_3_rows)
# 
# # 3. Quick Summary: How many people is this?
# nrow(sub_3_rows)

######################################################################################################

# error_rows <- data %>%
#   filter(Embarked == "" | is.na(Embarked))
# error_rows <- data %>%
#   filter(!Embarked %in% c("S", "C", "Q"))
# print(error_rows)
# Checking the rows with no generic S C Q label to see if correction is needed


data <- data %>%
  add_count(Ticket) %>%
  mutate(Ticket = n - 1) %>%
  select(-n)
# Swap the ticket number with the duplicate count

data <- data %>%
  mutate(Fare = Fare / (Ticket + 1))



# Merging the 2 columns by creating a new one and removing the original ones
data$SocialSize <- data$SibSp + data$Parch + data$Ticket
data$SibSp <- NULL
# removing prach after I calculate ages
data$Ticket <- NULL

data <- data %>%
  mutate(Sex = if_else(Sex == "male", 0, 1))
# swapping male and female to binary (female higher)

data <- data %>%
  mutate(Pclass = recode(Pclass, 
                         `1` = 4, 
                         `2` = 3, 
                         `3` = 1))
# Adjusting the hirearchy of classes with a wider gap for the third class



data <- data %>%
  mutate(Age = case_when(
    !is.na(Age) ~ Age,
    
    grepl("Mr\\.|Mrs\\.", Name) ~ 30,
    
    grepl("Master\\.", Name) ~ 10,
    
    grepl("Miss\\.", Name) & Parch >= 1 ~ 10,
    
    grepl("Miss\\.", Name) & Parch == 0 ~ 30,
    
    TRUE ~ 30 # deafult for a single person that is a Dr., so I assume he is about 30
  ))
# Names with specific starting points are assigned specific age

data <- data %>%
  mutate(GroupWeight = case_when(
    # Children under 14
    Age < 14 ~ 3,
    
    # Females 15 and older (Sex 1 = Female)
    Age >= 15 & Sex == 1 ~ 4,
    
    # Males 15 and older (Sex 0 = Male)
    Age >= 15 & Sex == 0 ~ 1,
    
    # Catch-all for anyone exactly between 14 and 15 (e.g., 14.5)
    TRUE ~ 2 
  ))
# Grouped Age and Sex

data$Parch <- NULL # finally we can delete the column

data$PassengerId <- NULL
data$Name <- NULL
data$Cabin <- NULL
data$Embarked <- NULL
data$Age <- NULL
data$Sex <- NULL
data$Fare <- NULL


head(data)
summary(data)




############################################################################################
# Training
############################################################################################


library(rpart)
library(rpart.plot)


# Growing the tree (tested minsplit 1, 10, 20, 30)
dtree_full <- rpart(Survived ~ ., 
                    method = "class", 
                    data = data,
                    control = rpart.control(minsplit = 20, cp = 0))

printcp(dtree_full)


best_cp <- 0.002193      
dtree_pruned <- prune(dtree_full, cp = best_cp)

# Plotting final tree
rpart.plot(dtree_pruned, type = 4, extra = 101, 
           fallen.leaves = FALSE, tweak = 1.4,
           main = "Pruned Decision Tree")



############################################################################################
# Training
############################################################################################
predictions <- predict(dtree_pruned, data, type = "class")
confusionMatrix(as.factor(predictions), as.factor(data$Survived), 
                positive = "1", 
                mode = "prec_recall")
