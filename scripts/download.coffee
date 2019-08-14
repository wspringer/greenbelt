scrapeIt = require 'scrape-it'
Bottleneck = require 'bottleneck/es5'
ProgressBar = require 'progress'
writeFile = require 'write'
download = require 'download'
path = require 'path'
_ = require 'lodash'

limiter = new Bottleneck(
  maxConcurrent: 1
  minTime: 333
)

downloadIndex = ->
  scrapeIt('https://www.greenbelt.org.uk/2019-lineup/', {
    artists: {
      listItem: 'ul.listing li'
      data: {
        url: {
          selector: 'a'
          attr: 'href'
        }
        slug: {
          selector: 'a'
          how: (el) -> 
            parts = el.attr('href').split('/')
            parts[parts.length - 2]
        }
        name: '.artist_name'
        image: {
          selector: '.artist_image'
          attr: 'data-src'
        }
      }
    }    
  })
  .then _.property 'data'

downloadDetails = (url) ->
  scrapeIt(url, {
    twitter: {
      selector: 'a:contains("Twitter")'
      how: (el) -> 
        if el.text() is '' then null
        else el.attr('href')
    }
    shows: {
      listItem: '#side_bar_content .shows'
      data: {
        title: 'h4'
        details: {
          selector: 'h3'
          how: (el) -> 
            [ location, tail ] = el.html().split('<br>')
            [ day, tail ] = tail.split(' ')
            [ time ] = tail.split('<')
            { location, day, time }
        }
        desc: {
          selector: 'p'
          how: 'html'
        }
      }
    }
  })
  .then _.property 'data'

downloadDetailsLtd = limiter.wrap(downloadDetails)  

downloadAll = ->
  index = await downloadIndex()
  await writeFile('data/index.json', JSON.stringify(index))  
  bar = new ProgressBar('[:bar] :percent :etas', { 
    total: index.artists.length
    complete: '☰'
    incomplete: ' '
    width: 30
  })
  await Promise.all(
    index.artists
    .map((artist) -> 
      Promise.all([
        downloadDetailsLtd(artist.url)
        download(artist.image).then((data) -> writeFile("data/#{artist.slug}/artist.jpg", data))
      ])
      .then ([details]) ->         
        bar.tick()
        if details.twitter is null then delete details.twitter
        writeFile("data/#{artist.slug}/artist.json", JSON.stringify(_.assign({}, artist, details)))
    )
  )

(->
  all = await downloadAll()
)()