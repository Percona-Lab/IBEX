module.exports = {
  run: [
    {
      method: "shell.run",
      params: {
        venv: "env",
        venv_python: "3.11",
        path: "app",
        message: [
          "uv pip install open-webui -U",
          "uv pip install onnxruntime==1.20.1 itsdangerous"
        ]
      }
    },
    {
      method: "shell.run",
      params: {
        message: "npm install --loglevel=error"
      }
    },
    {
      method: "shell.run",
      params: {
        message: "node create-env.js"
      }
    },
    {
      method: "notify",
      params: {
        html: "<b>IBEX installed!</b><br>Edit <b>~/.ibex-mcp.env</b> with your connector credentials, then click <b>Start</b>.",
        href: "start.js"
      }
    }
  ]
}
