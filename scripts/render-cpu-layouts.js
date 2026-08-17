const activity = require('../Model.js')

const sizes = {
  gap: 3,
  domainGap: 8,
  pad: 6,
  performance: 18,
  efficiency: 12,
  same: 12
}

const catalog = activity.previewCoreCatalog(sizes)
process.stdout.write(JSON.stringify(catalog, null, 2))
