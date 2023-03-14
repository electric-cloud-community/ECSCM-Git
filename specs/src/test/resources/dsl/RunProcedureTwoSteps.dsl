package dsl

def projName = args.projectName
def procName = args.procedureName
def subProcName = args.subProcedureName
def resName = args.resName ?: 'local'
def params = args.params

def parameters = [
        config             : '',
        commit             : '',
        clone              : '',
        overwrite          : '',
        depth              : '',
        tag                : '',
]

def options = [
        dest               : '',
        GitBranch          : '',
        GitRepo            : ''
]

project projName, {

    procedure procName, {

        resourceName = resName
        projectName = projName

        params.each { k, defaultValue ->
            formalParameter k, defaultValue: defaultValue, {
                type = 'textarea'
                expansionDeferred = '1'
            }
        }

        ['one', 'two'].eachWithIndex { nam, idx ->
            step 'step_'+nam, {
                description = ''
                subprocedure = subProcName
                subproject = '/plugins/ECSCM-Git/project'
                // subpluginKey = 'ECSCM-Git'
                // projectName = projName
                // resource = resName

                parameters.each { k, v ->
                    actualParameter k, (params[k] ?: '$[' + k + ']')
                }

                options.each { k, v ->
                    kIdx = k+'_'+idx
                    actualParameter k, (params[kIdx] ?: '$[' + kIdx + ']')
                }
            }
        }
    }
}