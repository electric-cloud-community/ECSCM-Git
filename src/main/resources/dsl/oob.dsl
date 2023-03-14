def storageProjectName = 'Electric Cloud'

project storageProjectName, {
  workspaceName = null
  resourceName = null

  procedure "Git Setup for DevOps Insight", {
    description = 'Utility procedure for creating a schedule for periodically retrieving git commit data from git repository and sending the data to the DevOps Insight server.'
    jobNameTemplate = ''
    projectName = storageProjectName
    resourceName = ''
    timeLimit = ''
    timeLimitUnits = 'minutes'
    workspaceName = ''

    formalParameter 'config', defaultValue: 'default', {
      description = 'The name for the ECSCM plugin configuration to use. This plugin configuration will be created if it does not already exist.'
      expansionDeferred = '0'
      label = 'Configuration name'
      required = '1'
      type = 'entry'
    }

    formalParameter 'credentialType', defaultValue: '', {
      description = 'Git Credential Type, "password" for password-based auth, "key" for SSH private key auth.'
      expansionDeferred = '0'
      label = "Git Credential Type"
      required = '0'
    }


    formalParameter 'credential', defaultValue: '', {
      description = 'Username and password/private key to connect to git repo. Required if the plugin configuration does not exist and needs to be created.'
      expansionDeferred = '0'
      label = "Git Credentials"
      required = '0'
      type = 'credential'
    }

    formalParameter 'privateKey', defaultValue: '', {
      description = 'Private key to log in to git repo with'
      expansionDeferred = '0'
      label = "Private key"
      required = '0'
    }

    formalParameter 'GitRepo', defaultValue: '', {
      type = 'entry'
      label = 'Remote Repository:'
      required = '1'
      description = 'The path or URL to the repository to pull from. ie: \'git://server/repo.git\'.'
    }

    formalParameter 'GitBranch', defaultValue: '', {
      type = 'entry'
      label = 'Remote Branch:'
      description = 'The name of the Git branch to use. ie: \'experimental\'.'
      required = '1'
    }


    formalParameter 'commit', defaultValue: '', {
        type = 'entry'
        label = 'Starting Commit:'
        description = 'Starting commit that will be used as entry point for reporting.'
    }

    formalParameter 'depth', defaultValue: '200', {
        type = 'entry'
        label = 'Initial Commit Count:'
        description = 'Initial count of commits that will be reported. Defaults to 200.'
    }

    formalParameter 'filePrefix', defaultValue: '', {
        type = 'entry'
        label = 'File Prefix:'
        description = '''
            If provided, matching string will be removed from file path before sending report.
            For example if file path is /opt/repo/file1, file prefix = /opt/repo will resolve it to /file1.
            Similarly file prefix = /opt/repo/ will resolve it to file1.'''
    }


    formalParameter 'commitURLTemplate', defaultValue: '%repoUrl%/%commitId%', {
        label = 'Commit URL Template'
        description = 'Template for a commit URL to be included in the report. Defaults to %repoUrl%/%commitId%'
        required = '0'
        type = 'entry'
    }


    formalParameter 'fileURLTemplate', defaultValue: '', {
        label = 'File URL Template'
        description = 'Template for a specific file URL to be included in the report. Defaults to %repoUrl%/%commitId%/%fileName%'
        required = '0'
        type = 'entry'
    }

    formalParameter 'fileDetails', defaultValue: '0', {
        type = 'checkbox'
        label = 'Include File Details:'
        required = '0'
        description = 'If set, the report will include file details.'
    }


    formalParameter 'CommandCenterProject', defaultValue: 'Release Command Center Schedules', {
      description = "Name of the project where the schedule for gathering commit data for the command center will be created. The project will be created if it does not already exist."
      expansionDeferred = '0'
      label = 'Project Name'
      required = '0'
      type = 'entry'
    }

    formalParameter 'ScheduleAndProcedureName', defaultValue: "Collect Reporting Data", {
      description = "Name of the schedule and the procedure that will be created for gathering commit data for the command center will be created."
      expansionDeferred = '0'
      label = "Schedule and procedure name to use"
      required = '1'
      type = 'entry'
    }

    formalParameter 'Schedule Frequency', defaultValue: '30', {
      description = 'Frequency (in minutes) for the schedule that will be created for gathering data.'
      expansionDeferred = '0'
      label = "Schedule Frequency"
      required = '1'
      type = 'entry'
    }

    ec_parameterForm = """<?xml version="1.0" encoding="UTF-8"?>
    <editor>
      <formElement>
        <type>entry</type>
        <label>Configuration name:</label>
        <property>config</property>
        <required>1</required>
        <documentation>The name for the ECSCM-Git plugin configuration to use. This plugin configuration will be created if it does not already exist.</documentation>
        <value>default</value>
      </formElement>
      <!-- what is done here is due to the form renderer does not render <credentialType>choose correclty -->
      <formElement>
          <type>select</type>
          <label>Credential type:</label>
          <property>credentialType</property>
          <required>0</required>
          <documentation>Type of credential; if set to "Private key", content of password field is considered a private key</documentation>
          <option><name>Password</name><value>password</value></option>
          <option><name>Private key</name><value>key</value></option>
      </formElement>
        <formElement>
          <type>credential</type>
          <credentialType>choose</credentialType>
          <label>Git Credentials:</label>
          <property>credential</property>
          <required>1</required>
          <documentation>Username and password to connect to Git repo. Required if the plugin configuration does not exist and needs to be created.</documentation>
        </formElement>
      <formElement>
          <type>textarea</type>
          <label>Private key:</label>
          <property>privateKey</property>
          <documentation>Private key to log in to Git repo. Required if the plugin configuration does not exist and needs to be created.</documentation>
          <required>0</required>
      </formElement>
      <formElement>
          <type>entry</type>
          <label>Remote Repository:</label>
          <property>GitRepo</property>
          <required>1</required>
          <documentation>The path or URL to the repository to pull from, e.g. 'https://github.com/username/reponame'.</documentation>
      </formElement>
      <formElement>
          <type>entry</type>
          <label>Remote Branch:</label>
          <property>GitBranch</property>
          <documentation>The name of the Git branch to use, e.g. 'experimental'. Defaults to 'master'.</documentation>
      </formElement>
      <formElement>
          <type>entry</type>
          <label>Starting Commit:</label>
          <property>commit</property>
          <documentation>Starting commit that will be used as entry point for reporting.</documentation>
      </formElement>
      <formElement>
          <type>entry</type>
          <label>Commit Count:</label>
          <property>depth</property>
        <documentation>Number of commits to be reported. The latest ones are reported. Defaults to 200.</documentation>
          <value>200</value>
      </formElement>
      <formElement>
          <type>entry</type>
          <label>File Prefix:</label>
          <property>filePrefix</property>
          <documentation>
              If provided, matching string will be removed from file path before sending report.
              For example if file path is /opt/repo/file1, file prefix = /opt/repo will resolve it to /file1.
              Similarly file prefix = /opt/repo/ will resolve it to file1.
          </documentation>
      </formElement>
      <formElement>
          <label>Commit URL Template</label>
          <property>commitURLTemplate</property>
          <required>0</required>
        <documentation>Template for a commit URL to be included in the report, e.g. '${repoUrl}/commit/${commitId}' for a Github repository.<br/>These URLs are also used to identify the commit in the reporting system, so they must be constructed in such a way so that they are unique across the repository.<br/>Defaults to ${repoUrl}/${commitId}</documentation>
          <type>entry</type>
      </formElement>
      <formElement>
          <label>File URL Template</label>
          <property>fileURLTemplate</property>
        <documentation>Template for a specific file URL to be included in the report, e.g. ${repoUrl}/blob/${commitId}/${fileName} for a Github repository.<br/>These URLs are also used to identify the specific file in a specific commit in the reporting system, so they must be constructed in such a way so that they are unique across the repository.<br/>Defaults to ${repoUrl}/${commitId}/${fileName}</documentation>
          <required>0</required>
          <type>entry</type>
      </formElement>
      <formElement>
          <type>checkbox</type>
          <label>Include File Details:</label>
          <property>fileDetails</property>
          <checkedValue>1</checkedValue>
          <required>0</required>
          <uncheckedValue>0</uncheckedValue>
          <documentation>If set, the report will include file details.</documentation>
          <value>0</value>
      </formElement>
      <formElement>
        <type>entry</type>
        <label>Project Name:</label>
        <property>CommandCenterProject</property>
        <required>0</required>
        <documentation>Name of the project where the schedule for gathering commit data for the command center will be created. The project will be created if it does not already exist.</documentation>
        <value>Release Command Center Schedules</value>
      </formElement>
      <formElement>
        <type>entry</type>
        <label>Schedule and procedure name to use:</label>
        <property>ScheduleAndProcedureName</property>
        <required>1</required>
        <documentation>Name of the schedule and the procedure that will be created for gathering commit data for the command center will be created.</documentation>
      <value>Collect Reporting Data - commits</value>
      </formElement>
      <formElement>
        <type>entry</type>
        <label>Schedule Frequency:</label>
        <property>Schedule Frequency</property>
        <required>1</required>
        <documentation>Frequency (in minutes) for the schedule that will be created for gathering data.</documentation>
        <value>30</value>
      </formElement>
    </editor>"""

    step 'check configuration', {
      description = ''
      alwaysRun = '0'
      broadcast = '0'
      command = '''use strict;
  use warnings;
  use ElectricCommander;

  my $configName = \'$[config]\';
  my $ec = ElectricCommander->new;
  my ($procName, $projName) = (\'$[ScheduleAndProcedureName]\', \'$[CommandCenterProject]\');

  my $pluginProjectName = $ec->getPlugin({pluginName => \'ECSCM\'})->findvalue(\'//projectName\')->string_value;
  my $configPath = "/projects/$pluginProjectName/scm_cfgs/$configName/scmPlugin";

  my $exists = 0;
  eval {
    my $value = $ec->getProperty($configPath)->findvalue(\'//value\')->string_value;
    die unless $value eq "ECSCM-Git";
    $exists = 1;
  };

  $ec->setProperty(\'/myJob/configDoesNotExist\', !$exists);
  eval{$ec->abortOnError(1);$ec->getProcedure($projName, $procName);1;}and do{bail_out("Procedure $procName already exists in $projName project.\n");};
  sub bail_out {
      my ($message) = @_;

      $ec->setProperty("/myJobStep/summary", $message);
      die $message;
  }
  '''
      condition = ''
      errorHandling = 'abortProcedureNow'
      exclusiveMode = 'none'
      logFileName = ''
      parallel = '0'
      postProcessor = ''
      precondition = ''
      projectName = storageProjectName
      releaseMode = 'none'
      resourceName = ''
      shell = 'ec-perl'
      subprocedure = null
      subproject = null
      timeLimit = ''
      timeLimitUnits = 'minutes'
      workingDirectory = ''
      workspaceName = ''
    }

    step 'create configuration', {
      description = ''
      alwaysRun = '0'
      broadcast = '0'
      command = '''
use strict;
use warnings;
use ElectricCommander;
my $ec = ElectricCommander->new;

my $configName = \'$[config]\';
my $credential = \'$[credential]\';
my $credentialType = \'$[credentialType]\';
my $privateKey = \'$[privateKey]\';

my $cred = $ec->getFullCredential($credential);
my $userName = $cred->findvalue("//userName");
my $password = $credentialType eq "key" ? $privateKey : $cred->findvalue("//password");

my $pluginProjectName = $ec->getPlugin({pluginName => "ECSCM-Git"})->findvalue(\'//projectName\')->string_value;
my $xpath = $ec->runProcedure($pluginProjectName,
            {procedureName => "CreateConfiguration",
           actualParameter => [
      {actualParameterName => "config", value => $configName},
      {actualParameterName => "credential", value => $credential},
      {actualParameterName => "credentialType", value => $credentialType},
      {actualParameterName => "desc", value => "Quickstart Git config"}],
                credential => [
    {'credentialName' => 'credential',
    'userName' => "$userName",
    'password' => "$password" }]
});

print "Errors: ", $ec->checkAllErrors($xpath);

'''
      condition = '$[/myJob/configDoesNotExist]'
      errorHandling = 'abortProcedureNow'
      exclusiveMode = 'none'
      logFileName = null
      parallel = '0'
      postProcessor = null
      precondition = ''
      projectName = storageProjectName
      releaseMode = 'none'
      resourceName = ''
      shell = 'ec-perl'
      subprocedure = null
      subproject = null
      timeLimit = ''
      timeLimitUnits = 'minutes'
      workingDirectory = null
      workspaceName = ''
    }

    step 'create procedure and schedule', {
      description = 'Creates a procedure for data gathering.'
      alwaysRun = '0'
      broadcast = '0'
      command = '''use strict;
  use warnings;
  use ElectricCommander;
  my $ec = ElectricCommander->new;

  my $configName = \'$[config]\';
  my $projectName = \'ECSCM-Git\';
  my $procedureProjectName = \'$[CommandCenterProject]\';
  my $procedureName = \'$[ScheduleAndProcedureName]\';
  my $frequency = \'$[Schedule Frequency]\';

  my $GitRepo = \'$[GitRepo]\';
  my $GitBranch = \'$[GitBranch]\';
  my $commit = \'$[commit]\';
  my $depth = \'$[depth]\';
  my $filePrefix = \'$[filePrefix]\';
  my $commitURLTemplate = \'$[commitURLTemplate]\';
  my $fileURLTemplate = \'$[fileURLTemplate]\';
  my $fileDetails = \'$[fileDetails]\';

  my $dsl = qq{
  project \'$procedureProjectName\', {
    resourceName = null
    workspaceName = null

    procedure \'$procedureName\', {
      description = \'\'
      jobNameTemplate = \'\'
      resourceName = \'\'
      timeLimit = \'\'
      timeLimitUnits = \'minutes\'
      workspaceName = \'\'

      step \'collect\', {
        description = \'\'
        alwaysRun = \'0\'
        broadcast = \'0\'
        command = null
        condition = \'\'
        errorHandling = \'failProcedure\'
        exclusiveMode = \'none\'
        logFileName = null
        parallel = \'0\'
        postProcessor = null
        precondition = \'\'
        releaseMode = \'none\'
        resourceName = \'\'
        shell = null
        subprocedure = \'CollectReportingData\'
        subproject = \'/plugins/ECSCM-Git/project\'
        timeLimit = \'\'
        timeLimitUnits = \'minutes\'
        workingDirectory = null
        workspaceName = \'\'

        actualParameter \'config\', \'$configName\'
        actualParameter \'commit\', \'$commit\'
        actualParameter \'commitURLTemplate\', \'$commitURLTemplate\'
        actualParameter \'debug\', \'0\'
        actualParameter \'depth\', \'$depth\'
        actualParameter \'fileDetails\', \'$fileDetails\'
        actualParameter \'filePrefix\', \'$filePrefix\'
        actualParameter \'fileURLTemplate\', \'$fileURLTemplate\'
        actualParameter \'GitBranch\', \'$GitBranch\'
        actualParameter \'GitRepo\', \'$GitRepo\'
      }
    }

    schedule \'$procedureName\', {
      description = \'\'
      applicationName = null
      applicationProjectName = null
      beginDate = \'\'
      endDate = \'\'
      environmentName = null
      environmentProjectName = null
      environmentTemplateName = null
      environmentTemplateProjectName = null
      environmentTemplateTierMapName = null
      interval = \'$frequency\'
      intervalUnits = \'minutes\'
      misfirePolicy = \'ignore\'
      monthDays = \'\'
      pipelineName = null
      priority = \'normal\'
      procedureName = \'$procedureName\'
      processName = null
      releaseName = null
      rollingDeployEnabled = null
      rollingDeployManualStepAssignees = null
      rollingDeployManualStepCondition = null
      rollingDeployPhases = null
      scheduleDisabled = \'0\'
      snapshotName = null
      startTime = \'\'
      startingStage = null
      startingStateName = null
      stopTime = \'\'
      timeZone = \'\'
      weekDays = \'\'
      workflowName = null

      // Custom properties

      property \'ec_customEditorData\', {

        // Custom properties
        formType = \'standard\'
      }
    }
  }

  };

  $ec->evalDsl($dsl);

  print "Created project $procedureProjectName\\n";
  print "Created procedure $procedureName\\n";
  print "Created schedule $procedureName\\n";

  my $ecSummary = get_summary($procedureProjectName, $procedureName);
  $ec->setProperty("/myJobStep/summary", $ecSummary);
  use URI::Escape;
  my ($procedureLink, $scheduleLink);
  $ec->setProperty("/myJob/report-urls/Procedure: $procedureName", $procedureLink);
  $ec->setProperty("/myJob/report-urls/Schedule: $procedureName", $scheduleLink);
  eval {
        my $link1 = qq|<html><span class="jobStep_statusText"><a target="_blank" href="$procedureLink">$procedureName</a></span><br /></html>|;
        my $link2 = qq|<html><span class="jobStep_statusText"><a target="_blank" href="$scheduleLink">$procedureName</a></span><br /></html>|;
        $ec->setProperty("/myPipelineStageRuntime/ec_summary/Procedure $procedureName:", $link1);
        $ec->setProperty("/myPipelineStageRuntime/ec_summary/Schedule $procedureName:", $link2);
        };
  sub get_summary {
    my ($projectName, $objectName) = @_;
    my $template = q|/commander/link/%s/projects/%s/%s/%s|;

    $procedureLink = sprintf($template, q|procedureDetails|, uri_escape($projectName), q|procedures|, uri_escape($objectName));
    $scheduleLink = sprintf($template, q|editSchedule|, uri_escape($projectName), q|schedules|, uri_escape($objectName));
    my $html = qq|
<html>
Project: $projectName<br/>
Created procedure: <a target="_blank" href="$procedureLink">$objectName</a><br />
Created schedule: <a target="_blank" href="$scheduleLink">$objectName</a><br />
</html>
|;
    return $html;
}
  '''
      condition = ''
      errorHandling = 'failProcedure'
      exclusiveMode = 'none'
      logFileName = ''
      parallel = '0'
      postProcessor = ''
      precondition = ''
      projectName = storageProjectName
      releaseMode = 'none'
      resourceName = ''
      shell = 'ec-perl'
      subprocedure = null
      subproject = null
      timeLimit = ''
      timeLimitUnits = 'minutes'
      workingDirectory = ''
      workspaceName = ''
    }

    attachParameter(
        projectName: projectName,
        formalParameterName: 'credential',
        procedureName: "Git Setup for DevOps Insight",
        stepName: 'create configuration'
    )

  }

}

