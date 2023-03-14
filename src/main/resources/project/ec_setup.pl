my $projPrincipal = "project: $pluginName";
my $ecscmProj = '$[/plugins/ECSCM/project]';

if ($promoteAction eq 'promote') {
    # Register our SCM type with ECSCM
    $batch->setProperty("/plugins/ECSCM/project/scm_types/@PLUGIN_KEY@", "Git");

    # Give our project principal execute access to the ECSCM project
    my $xpath = $commander->getAclEntry("user", $projPrincipal,
                                        {projectName => $ecscmProj});
    if ($xpath->findvalue('//code') eq 'NoSuchAclEntry') {
        $batch->createAclEntry("user", $projPrincipal,
                               {projectName => $ecscmProj,
                                executePrivilege => "allow"});
    }

} elsif ($promoteAction eq 'demote') {
    # unregister with ECSCM
    $batch->deleteProperty("/plugins/ECSCM/project/scm_types/@PLUGIN_KEY@");

    # remove permissions
    my $xpath = $commander->getAclEntry("user", $projPrincipal,
                                        {projectName => $ecscmProj});
    if ($xpath->findvalue('//principalName') eq $projPrincipal) {
        $batch->deleteAclEntry("user", $projPrincipal,
                               {projectName => $ecscmProj});
    }

}

# WEbhook
$batch->setProperty('/server/ec_endpoints/githubWebhook', '@PLUGIN_KEY@');

# $batch->setProperty("/projects/$pluginName/ec_endpoints");

# EF Server retrieves property /plugins/ECSCM-Git/project/ec_endpoints/githubWebhook/POST/script which contains DSL code
# If there is query parameter "config", EF Server retrieves property /plugins/ECSCM-Git/project/ec_endpoints/githubWebhook/POST/configurationMetadata and takes pluginKey_2 (e.g. ECSCM) and configurationPath from it
# EF Server retrieves configuration /plugins/pluginKey_2/project/{configurationPath} properties
# EF Server retrieves all credentials from the plugin pluginKey_2 with the name starting with <configname>, i.e. githubConfig, githubConfig_webhookSecret if the configname = githubConfig
# If pluginKey_2 is not provided, then pluginKey_2 = pluginKey_1
# EF Server runs DSL passing HTTP Request details (headers, payload, URL, method) and configuration (configuration properties, credentials), i.e. {payload: ..., headers: [...], method: 'POST', url: '<URL>/githubWebhook?param1=1, ....', config: [field1: 'value1', credentials: [cred1, cred2]]}
# DSL validates the payload using the credential from the passed configuration, then launches ECSCM:ProcessWebHookSchedules procedure passing {webhookData, webhookSchedulesSearchParams}, i.e.
# webhookData = {commitId: ..., author: ..., authorEmail: .....}, webhookSchedulesSearchParams = {event: 'push', action: '', projectName: 'repositoryName', eventSource: 'github'}
# DSL returns data for HTTP Response: {code: ..., payload: ...., headers: ...}
# Procedure ECSCM:ProcessWebHookSchedules filters schedules based on webhookSchedulesSearchParams parameter and launches them passing webhookData parameter.




# Unregister current and past entries first.
$batch->deleteProperty("/server/ec_customEditors/pickerStep/ECSCM-Git - Checkout");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/ECSCM-Git - Preflight");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/ECSCM-Git - CollectReportingData");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/Git - Checkout");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/Git - CollectReportingData");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/Git - Preflight");

my %Checkout = (
    label       => "Git - Checkout",
    procedure   => "CheckoutCode",
    description => "Checkout code from Git.",
    category    => "Source Code Management"
);

my %CollectReportingData = (
    label       => "Git - Collect Reporting Data",
    procedure   => "CollectReportingData",
    description => "Collects reporting data",
    category    => "Resource Management"
);

my %Preflight = (
	label 		=> "Git - Preflight",
	procedure 	=> "Preflight",
	description => "Checkout code from Git during Preflight",
	category 	=> "Source Code Management"
);
@::createStepPickerSteps = (
    \%Checkout,
    \%CollectReportingData,
    \%Preflight
);
