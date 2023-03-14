use strict;
use warnings;
use ElectricCommander;
use JSON;
use Data::Dumper;

my $ec = ElectricCommander->new;
my $rawHeaders = $ec->getProperty('rawHeaders')->findvalue('//value') . '';
my $rawPayload = $ec->getProperty('rawPayload')->findvalue('//value') . '';
my $schedulesSearchParameters = $ec->getProperty('schedulesSearchParameters')->findvalue('//value') . '';
my $rawEventData = $ec->getProperty('eventData')->findvalue('//value') . '';


print "Raw Headers: $rawHeaders\n";
print "Raw Payload: $rawPayload\n";
print "Schedules Search Parameters: $schedulesSearchParameters\n";


my $searchParams = decode_json($schedulesSearchParameters);
print Dumper $searchParams;

my $schedules = $ec->findObjects('schedule',
        {filter => [{
            propertyName => 'webhookEnabled',
            operator => 'equals',
            operand1 => '1'}]});

for my $schedule ($schedules->findnodes('//schedule')) {
    my $scheduleName = $schedule->findvalue('scheduleName') . '';
    my $projectName = $schedule->findvalue('projectName') . '';
    my $eventType = $ec->getProperty("/projects/$projectName/schedules/$scheduleName/ec_customEditorData/ec_webhookEventType")->findvalue('//value') . '';
    my $eventProject = $ec->getProperty("/projects/$projectName/schedules/$scheduleName/ec_customEditorData/ec_webhookThirdPartyProject")->findvalue('//value') . '';

    if ($searchParams->{eventType} eq $eventType && $searchParams->{repositoryName} eq $eventProject) {
        print "Found webhook schedule: $projectName:$scheduleName\n";
        my $procedureName = $schedule->findvalue('//procedureName') . '';

        my $formalParameters = $ec->getFormalParameters({projectName => $projectName, scheduleName => $scheduleName});

        # my $actualParameters = [];
        # my $payload = decode_json($rawPayload);
        # for my $formalParameter ($formalParameters->findnodes('//formalParameter')) {
        #     my $name = $formalParameter->findvalue('formalParameterName') . '';
        #     if ($name eq 'rawPayload') {
        #         push @$actualParameters, {actualParameterName => 'rawPayload', value => $rawPayload};
        #     }
        #     if ($name eq 'commitHash') {
        #         # TODO this should actually be in the DSL, placing it here for the sake of drafting speed
        #         push @$actualParameters, {actualParameterName => 'commitHash', value => $payload->{head_commit}->{id}};
        #     }
        # }
        # print "Actual Parameters:\n";
        # print Dumper $actualParameters;
        # TODO pass raw payload to the procedure/pipeline/whatever
        my $xpath = $ec->runProcedure({
            projectName => $projectName,
            scheduleName => $scheduleName,
            # procedureName => $procedureName,
            # actualParameter => $actualParameters
        });
        # print "Launched schedule $projectName: $scheduleName\n";
        my $jobId = $xpath->findvalue('//jobId');

        my $eventData = decode_json($rawEventData);
        $ec->setProperty({
            jobId => $jobId,
            propertyName => 'ec_githubWebhookPayload',
            value => $rawPayload});
        for my $field (keys %$eventData) {
            $ec->setProperty({jobId => $jobId, propertyName => "ec_webhookEventData$field", value => $eventData->{$field}});
        }
    }
    else {
        print "Schedule $projectName:$scheduleName is not bound to this webhook\n";
    }
}
