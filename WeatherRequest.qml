import Quickshell.Io

// URLs may contain credentials. Only send them through the child's stdin.
Process {
  property string requestConfig: ""
  onStarted: {
    write(requestConfig)
    requestConfig = ""
    stdinEnabled = false
  }
}
