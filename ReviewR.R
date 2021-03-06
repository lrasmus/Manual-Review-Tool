# ReviewR: A light-weight, portable tool for reviewing individual patient records
#
# https://zenodo.org/badge/latestdoi/140004344
#
# This is a shiny tool that allows for manual review of the MIMIC-III (https://mimic.physionet.org/) or 
# OMOP (https://www.ohdsi.org/data-standardization/the-common-data-model/) database.  Current support is
# for Postgres and Google BigQuery, with more to come in the future. 
#
# This is a work in progress and thus there are no guarantees of functionality or accuracy. Use at your own risk.


source('lib/reviewr-core.R')

# We will make sure all required packages are installed and loaded
check.packages(c("shiny", "shinyjs", "shinydashboard", "shinycssloaders",
                 "tidyverse", "DT", "dbplyr", "magrittr", "readr", "configr"))

# Define server logic 
server <- function(input, output, session) {
  options("httr_oob_default" = TRUE)

  # Attempt to load the ReviewR connection configuration from config.yml.  If it doesn't exist, the rest of the UI
  # will render to allow the user to specify the database connection details.
  reviewr_config <- load_reviewr_config()
  
  # Initialize a collection of reactive values.  These are going to be used across our two different connection
  # methods (through config.yml, or from a form) to trigger UI updates.
  values <- reactiveValues()
  
  output$title = renderText({ paste0("ReviewR (", toupper(values$data_model), ")") })
  
  render_data_tables <- NULL
  has_projects = FALSE
  output$has_projects <- reactive({ has_projects })

  output$subject_id_output <- renderText({paste("Subject ID - ",input$subject_id)})
  output$subject_id <- renderText({input$subject_id})
  
  patient_nav_previous = tags$div(actionButton("prev_patient",
    HTML('<div class="col-sm-4"><i class="fa fa-angle-double-left"></i> Previous</div>')))
  patient_nav_next = div(actionButton("next_patient",
    HTML('<div class="col-sm-4">Next <i class="fa fa-angle-double-right"></i></div>')))
  output$patient_navigation_list=renderUI({
    div(column(1,offset=0,patient_nav_previous),column(1,offset=9,patient_nav_next))
  })
  
  # Because we want to use uiOutput for the patient chart panel in multiple locations in the UI,
  # we need to implement the workaround described here (https://github.com/rstudio/shiny/issues/743)
  # where we actually render multiple outputs for each use.
  patient_chart_panel = reactive({
    table_names <- get_review_table_names(values$data_model)
    tabs <- lapply(table_names, function(id) { create_data_panel(id, paste0(id, "_tbl"))})
    panel <- div(
      fluidRow(column(12, h2(textOutput("subject_id_output")))),
      br(),
      fluidRow(column(12, do.call(tabsetPanel, tabs)))
    ) #div
    panel
  })
  output$patient_chart_panel_abstraction <- renderUI({ patient_chart_panel() })
  output$patient_chart_panel_no_abstraction <- renderUI({ patient_chart_panel() })
  
  output$selected_project_title <- renderText({
    ifelse(is.null(input$project_id),
           "(No project selected)",
           paste("Project: ", project_list[project_list$id == input$project_id, "name"]))
  })
  output$selected_project_id <- renderText({input$project_id})
  
  # This instantiation of the home navigation_links control will only be used if the user
  # hasn't specified a config.yml within their directory.  Default behavior is to give
  # them a login screen, but checks below will determine if we can skip this and have a
  # connection already established.
  output$navigation_links <- renderUI({
    div(
      selectInput("data_model", "Select your data model:",
                  c("OMOP" = "omop",
                    "MIMIC" = "mimic")),
      selectInput("db_type", "Select your database:",
                  c("PostgreSQL" = "postgres",
                    "BigQuery" = "bigquery")),
      conditionalPanel(
        condition = "(input.db_type == 'postgres')",
        textInput("user", "User:"),
        passwordInput("password", "Password:"),
        textInput("host", "Database Host/Server:", "localhost"),
        textInput("port", "Port:", "5432"),
        textInput("dbname", "Database Name:")
      ),
      conditionalPanel(
        condition = "(input.db_type == 'bigquery')",
        textInput("project_id", "Project ID:"),
        textInput("dataset", "Dataset:")
      ),
      actionButton("connect", "Connect")
    )
  })
  
  observeEvent(input$viewProjects, {
    updateTabsetPanel(session = session, inputId = "tabs", selected = "projects")
  })
  observeEvent(input$viewPatients, {
    updateTabsetPanel(session = session, inputId = "tabs", selected = "patient_search")
  })
  
  if (!is.null(reviewr_config)) {
    reviewr_config <- initialize(reviewr_config)
    values$data_model <- reviewr_config$data_model
    render_data_tables = get_render_data_tables(reviewr_config$data_model)
    output = render_data_tables(input, output, reviewr_config)
    
    output$navigation_links <- renderUI({
      fluidRow(class="home_container",
               column(8,
                      div(class="jumbotron home_panel",
                          h3("Browse Patients"),
                          div(paste0("Navigate through the full list of patients"), class="lead"),
                          actionLink(inputId = "viewPatients", label = "View Patients", class="btn btn-primary btn-lg"))))
    })
  }
  
  observeEvent(input$connect, {
    reviewr_config = isolate({ list(
      data_model=input$data_model,
      db_type=input$db_type,
      database=input$dbname,
      host=input$host,
      port=input$port,
      user=input$user,
      password=input$password,
      project = input$project_id,
      dataset = input$dataset)
    })
    
    # Set our reactive values based on the input
    values$data_model <- reviewr_config$data_model
    
    tryCatch({
      # Initialize the ReviewR application
      reviewr_config <- initialize(reviewr_config)
      render_data_tables = get_render_data_tables(reviewr_config$data_model)
      output$navigation_links <- renderUI({
        fluidRow(class="home_container",
                 column(8,
                        div(class="jumbotron home_panel",
                            h3("Browse Patients"),
                            div(paste0("Navigate through the full list of patients"), class="lead"),
                            actionLink(inputId = "viewPatients", label = "View Patients", class="btn btn-primary btn-lg"))))
      })
      output = render_data_tables(input, output, reviewr_config)
    },
    error=function(e) {
      showNotification(
        paste("There was an error when trying to connect to the database.  Please make sure that you have configured the application correctly, and that the database is running and accessible from your machine.\r\n\r\n",
              "You will need to resolve the connection issue before ReviewR will work properly.  If you need help configuring ReviewR, please see the README.md file that is packaged with the repository.\r\n\r\nError:\r\n", e),
        duration = NULL, type = "error", closeButton = TRUE)
    })
  })
  
  outputOptions(output, "has_projects", suspendWhenHidden = FALSE)
  
  # When the Shiny session ends, perform cleanup (closing connections, removing objects from environment)
  session$onSessionEnded(function() {
    if (!is.null(reviewr_config) & !is.null(reviewr_config$connection)) {
      dbDisconnect(reviewr_config$connection)
    }
    rm(list = ls())
  })
}


# Define UI for application 
ui <- dashboardPage(
  dashboardHeader(title = textOutput('title')),
  dashboardSidebar(
    sidebarMenu(
      id = "tabs",
      menuItem("Home", tabName = "home", icon = icon("home")),
      menuItem("Patient Search", tabName = "patient_search", icon = icon("users")),
      menuItem("Chart Review", icon = icon("table"), tabName = "chart_review")
    )
  ),
  dashboardBody(
    tags$head(
      tags$link(rel = "stylesheet", type = "text/css", href = "app.css")),
    
    tabItems(
      tabItem(tabName = "home",
              h2("Welcome to ReviewR"),
              uiOutput("navigation_links")
      ), #tabItem
      tabItem(tabName = "projects",
              conditionalPanel(
                condition = "!(input.project_id)",
                h2("Select a project to work on"),
                withSpinner(DT::dataTableOutput('projects_tbl'))
              ),
              conditionalPanel(
                condition = "(input.project_id)",
                h2(textOutput("selected_project_title")),
                HTML("<a id='reset_project_id' href='#' onclick='Shiny.onInputChange(\"project_id\", null);'>View All Projects</a>"),
                div(id="active_cohort",
                    withSpinner(DT::dataTableOutput('cohort_tbl')))
              )
      ),
      tabItem(tabName = "patient_search",
              h2("Select a patient to view"),
              withSpinner(DT::dataTableOutput('all_patients_tbl'))
      ),
      tabItem(tabName = "chart_review",
              conditionalPanel(
                condition = "input.subject_id == null || input.subject_id == undefined || input.subject_id == ''",
                h4("Please select a patient from the 'Patient Search' tab")
              ),
              conditionalPanel(
                condition = "input.subject_id != ''",
                #uiOutput("patient_navigation_list"),
                uiOutput("patient_chart_panel_no_abstraction")
              ) #conditionalPanel
      ) #tabItem
    )
  )
)


# Run the application 
shinyApp(ui = ui, server = server)

