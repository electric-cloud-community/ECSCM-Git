package dsl
def pipelineName = args.pipelineName
def importedProjectName = args.projectName

pipeline pipelineName, {
  description = ''
  disableRestart = '0'
  enabled = '1'
  overrideWorkspace = '0'
  pipelineRunNameTemplate = null
  projectName = importedProjectName
  releaseName = null
  skipStageMode = 'ENABLED'
  templatePipelineName = null
  templatePipelineProjectName = null
  type = null
  workspaceName = null

  formalParameter 'ec_stagesToRun', defaultValue: null, {
    expansionDeferred = '1'
    label = null
    orderIndex = null
    required = '0'
    type = null
  }

  stage 'Stage 1', {
    colorCode = '#00adee'
    completionType = 'auto'
    condition = null
    duration = null
    parallelToPrevious = null
    pipelineName = pipelineName
    plannedEndDate = null
    plannedStartDate = null
    precondition = null
    resourceName = null
    waitForPlannedStartDate = '0'

    gate 'PRE', {
      condition = null
      precondition = null
      }

    gate 'POST', {
      condition = null
      precondition = null
      }

    task 'Print webhook data', {
      description = ''
      actualParameter = [
        'commandToRun': '''echo '$[webhookData]' ''',
        'shellToUse': null,
      ]
      advancedMode = '0'
      afterLastRetry = null
      alwaysRun = '0'
      condition = null
      deployerExpression = null
      deployerRunType = null
      duration = null
      emailConfigName = null
      enabled = '1'
      environmentName = null
      environmentProjectName = null
      environmentTemplateName = null
      environmentTemplateProjectName = null
      errorHandling = 'stopOnError'
      gateCondition = null
      gateType = null
      groupName = null
      groupRunType = null
      insertRollingDeployManualStep = '0'
      instruction = null
      notificationEnabled = null
      notificationTemplate = null
      parallelToPrevious = null
      plannedEndDate = null
      plannedStartDate = null
      precondition = null
      requiredApprovalsCount = null
      resourceName = ''
      retryCount = null
      retryInterval = null
      retryType = null
      rollingDeployEnabled = null
      rollingDeployManualStepCondition = null
      skippable = '0'
      snapshotName = null
      stageSummaryParameters = null
      startingStage = null
      subErrorHandling = null
      subapplication = null
      subpipeline = null
      subpluginKey = 'EC-Core'
      subprocedure = 'RunCommand'
      subprocess = null
      subproject = null
      subrelease = null
      subreleasePipeline = null
      subreleasePipelineProject = null
      subreleaseSuffix = null
      subservice = null
      subworkflowDefinition = null
      subworkflowStartingState = null
      taskProcessType = null
      taskType = 'COMMAND'
      triggerType = null
      useApproverAcl = '0'
      waitForPlannedStartDate = '0'
    }
  }

  // Custom properties

  property 'ec_counters', {

    // Custom properties
    pipelineCounter = '14'
  }
}
