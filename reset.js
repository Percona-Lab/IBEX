module.exports = {
  run: [
    {
      method: "fs.rm",
      params: {
        path: "app"
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
