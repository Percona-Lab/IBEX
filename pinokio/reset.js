module.exports = {
  run: [
    {
      method: "shell.run",
      params: {
        message: "{{platform === 'win32' ? 'if exist app rmdir /s /q app' : 'rm -rf app'}}"
      }
    },
    {
      method: "notify",
      params: {
        html: "<b>Factory reset complete.</b> Click Install to set up IBEX again."
      }
    }
  ]
}
