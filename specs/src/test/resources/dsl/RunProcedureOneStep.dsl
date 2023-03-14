package dsl

def projName = args.projectName
def procName = args.procedureName
def subProcName = args.subProcedureName
def resName = args.resName ?: 'local'
def params = args.params

project projName, {
    procedure procName, {
        resourceName = resName

        step procName, {
            description = ''
            subprocedure = subProcName
            subproject = '/plugins/ECSCM-Git/project'

            params.each { name, defValue ->
                actualParameter name, '$[' + name + ']'
            }
        }

        params.each {name, defValue ->
            formalParameter name, defaultValue: defValue, {
                type = 'textarea'
            }
        }
    }
}
