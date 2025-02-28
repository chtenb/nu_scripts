export def 'str max-length' [] {
    $in | reduce -f 0 {|x, a|
        if ($x|is-empty) { return $a }
        let l = ($x | str length)
        if $l > $a { $l } else { $a }
    }
}

export def index-need-update [index path] {
    let ts = do -i { ls $path | sort-by modified | reverse | get 0.modified }
    if ($ts | is-empty) { return false }
    let tc = do -i { ls $index | get 0.modified }
    if not (($index | path exists) and ($ts < $tc)) {
        mkdir (dirname $index)
        return true
    }
    return false
}

def "nu-complete ssh host" [] {
    rg -LNI '^Host [a-z0-9_\-\.]+' ~/.ssh | lines | each {|x| $x | split row ' '| get 1}
}

export def parse-ssh-file [group] {
    $in
    | parse -r '(?P<k>Host|HostName|User|Port|IdentityFile)\s+(?P<v>.+)'
    | append { k: Host, v: null}
    | reduce -f { rst: [], item: {Host: null} } {|it, acc|
          if $it.k == 'Host' {
              $acc | upsert rst ($acc.rst | append $acc.item)
                   | upsert item { Host : $it.v, HostName: null, Port: null, User: null, IdentityFile: null, Group: $group }
          } else {
              $acc | upsert item ($acc.item | upsert $it.k $it.v)
          }
      }
    | get rst
    | where {|x| not (($x.Host | is-empty) or $x.Host =~ '\*')}
}

export def ssh-list [] {
    rg -L -l 'Host' ~/.ssh
    | lines
    | each {|x| cat $x | parse-ssh-file $x}
    | flatten
}

def fmt-group [p] {
    $p | str replace $"($env.HOME)/.ssh/" ''
}

def "ssh-hosts" [] {
    let cache = $'($env.HOME)/.cache/nu-complete/ssh.json'
    if index-need-update $cache ~/.ssh/**/* {
        let data = (ssh-list | each {|x|
                let uri = $"($x.User)@($x.HostName):($x.Port)"
                {
                    value: $x.Host,
                    uri: $uri,
                    group: $"(fmt-group $x.Group)",
                    identfile: $"($x.IdentityFile)",
                }
        })

        let max = {
            value: ($data.value | str max-length),
            uri: ($data.uri | str max-length),
            group: ($data.group | str max-length),
            identfile: ($data.identfile | str max-length),
        }

        {max: $max, completion: $data} | save -f $cache
    }

    cat $cache | from json
}

def "nu-complete ssh" [] {
    let data = (ssh-hosts)
    $data.completion
    | each { |x|
        let uri = ($x.uri | str lpad -l $data.max.uri -c ' ')
        let group = ($x.group | fill -w $data.max.group -c ' ' -a l)
        let id = ($x.identfile | fill -w $data.max.identfile -c ' ' -a l)
        {value: $x.value, description: $"\t($uri) ($group) ($id)" }
    }
}

export extern ssh [
    host: string@"nu-complete ssh"      # host
    ...cmd                              # cmd
    -v                                  # verbose
    -i: string                          # key
    -p: int                             # port
    -N                                  # n
    -T                                  # t
    -L                                  # l
    -R                                  # r
    -D                                  # d
    -J: string                          # j
    -W: string                          # w
]


def "nu-complete scp" [cmd: string, offset: int] {
    let argv = ($cmd | str substring [0 $offset] | split row ' ')
    let p = if ($argv | length) > 2 { $argv | get 2 } else { $argv | get 1 }
    let ssh = (ssh-hosts | get completion
        | each {|x| {value: $"($x.value):" description: $x.uri} }
    )
    let n = ($p | split row ':')
    if $"($n | get 0):" in ($ssh | get value) {
        ^ssh ($n | get 0) $"sh -c 'ls -dp ($n | get 1)*'"
        | lines
        | each {|x| $"($n | get 0):($x)"}
    } else {
        let files = do -i {
            ls -a $"($p)*"
            | each {|x| if $x.type == dir { $"($x.name)/"} else { $x.name }}
        }
        $files | append $ssh
    }
}

export def scp [
    lhs: string@"nu-complete scp",
    rhs: string@"nu-complete scp"
] {
    ^scp -r $lhs $rhs
}
