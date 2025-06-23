const cds = require('@sap/cds')

module.exports = class CatalogService extends cds.ApplicationService { init() {



  this.on ('hello', async (req) => {
    console.log('On hello', req.data)
    return `Hello! ${req.user.id}`
  })

  return super.init()
}}
