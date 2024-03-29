initialized    = false
currentState   = null
referer        = document.location.href
loadedAssets   = null
pageCache      = {}
createDocument = null
requestMethod  = document.cookie.match(/request_method=(\w+)/)?[1].toUpperCase() or ''
xhr            = null
pageTreeUrl    = '/local_storage_sync'
url_counter    = { x: 0 }

visit = (url) ->
  if browserSupportsPushState && browserIsntBuggy
    cacheCurrentPage()
    reflectNewUrl url
    needsRefresh
      yes: ->
        fetchReplacement url
      no: ->
        fetchFromLocalStore url
  else
    document.location.href = url

fetchReplacement = (url) ->
  triggerEvent 'page:fetch'

  # Remove hash from url to ensure IE 10 compatibility
  safeUrl = removeHash url

  xhr?.abort()
  xhr = new XMLHttpRequest
  xhr.open 'GET', safeUrl, true
  xhr.setRequestHeader 'Accept', 'text/html, application/xhtml+xml, application/xml'
  xhr.setRequestHeader 'X-XHR-Referer', referer

  xhr.onload = =>
    triggerEvent 'page:receive'

    if invalidContent(xhr) or assetsChanged (doc = createDocument xhr.responseText)
      document.location.reload()
    else
      # cache page in local store:
      cacheInLocalStore(safeUrl, xhr)

      changePage extractTitleAndBody(doc)
      reflectRedirectedUrl xhr
      if document.location.hash
        document.location.href = document.location.href
      else
        resetScrollPosition()
      triggerEvent 'page:load'

  xhr.onloadend = -> xhr = null
  xhr.onabort   = -> rememberCurrentUrl()
  xhr.onerror   = -> document.location.href = url

  xhr.send()

prefetchPages = ->
  if(!localStorage["data_synced"] || localStorage["data_synced"] != "true")

    localStorage.setItem('prefetch-counter', 0)

    xhr?.abort()
    xhr = new XMLHttpRequest
    xhr.open 'GET', pageTreeUrl, true
    xhr.setRequestHeader 'Accept', 'text/html, application/xhtml+xml, application/xml'
    xhr.setRequestHeader 'X-XHR-Referer', referer

    xhr.onload = =>
      urls = JSON.parse(xhr.responseText).page_tree
      url_counter.count = urls.length

      for url in urls
        prefetchPage(url)

    xhr.send()

logPrefetchCompletion = () ->
  if url_counter.count == parseInt(localStorage.getItem('prefetch-counter'))
    localStorage.setItem("data_synced", "true")

prefetchPage = (url) ->
  # Remove hash from url to ensure IE 10 compatibility
  safeUrl = removeHash url

  prefetchRequest?.abort()
  prefetchRequest = new XMLHttpRequest
  prefetchRequest.open 'GET', safeUrl, true
  prefetchRequest.setRequestHeader 'Accept', 'text/html, application/xhtml+xml, application/xml'
  prefetchRequest.setRequestHeader 'X-prefetchRequest-Referer', referer

  prefetchRequest.onload = =>
    cacheInLocalStore(safeUrl, prefetchRequest)

  prefetchRequest.onloadend = ->
    prefetchRequest = null
    localStorage.setItem('prefetch-counter', parseInt(localStorage.getItem('prefetch-counter')) + 1)
    triggerEvent 'page:prefetched'

  prefetchRequest.send()

cacheInLocalStore = (url, xhr) ->
  localStorage.setItem(url, xhr.responseText)
  localStorage.setItem('etag-' + url, xhr.getResponseHeader('Etag'))

needsRefresh = (callbacks) ->
  url = document.location.href
  if localStorage.getItem(url)?
    headRequest?.abort()
    headRequest = new XMLHttpRequest
    headRequest.open 'GET', url, true
    headRequest.setRequestHeader 'Accept', 'text/html, application/xhtml+xml, application/xml'
    headRequest.setRequestHeader 'X-XHR-Referer', referer
    headRequest.setRequestHeader 'If-None-Match', localStorage.getItem('etag-' + url)

    headRequest.onreadystatechange = ->
      if headRequest.readyState == 4
        if headRequest.status != 304
          callbacks.yes()
        else
          callbacks.no()

    headRequest.send()
  else
    callbacks.yes()

fetchFromLocalStore = (url) ->
  safeUrl = removeHash url
  stored_page = localStorage.getItem(safeUrl)
  triggerEvent 'page:receive'
  doc = createDocument(stored_page)
  changePage extractTitleAndBody(doc)
  reflectRedirectedUrl xhr
  if document.location.hash
    document.location.href = document.location.href
  else
    resetScrollPosition()
  triggerEvent 'page:load'

fetchHistory = (state) ->
  cacheCurrentPage()

  #if page = pageCache[state.position]
    #xhr?.abort()
    #changePage page.title, page.body
    #recallScrollPosition page
    #triggerEvent 'page:restore'
  #else

  needsRefresh
    yes: ->
      fetchReplacement document.location.href
    no: ->
      fetchFromLocalStore document.location.href

cacheCurrentPage = ->
  rememberInitialPage()

  pageCache[currentState.position] =
    url:       document.location.href,
    body:      document.body,
    title:     document.title,
    positionY: window.pageYOffset,
    positionX: window.pageXOffset

  constrainPageCacheTo(10)

constrainPageCacheTo = (limit) ->
  for own key, value of pageCache
    pageCache[key] = null if key <= currentState.position - limit
  return

changePage = (newPage) ->
  containerNode = $(document).find('[data-turbolinks-offline-container]').first()
  content = $(newPage[1]).find('[data-turbolinks-offline-container]').html()

  if containerNode?
    # sadly, I had to use jquery here o_O
    containerNode.html(content)
  else
    document.documentElement.replaceChild body, document.body

  document.title = newPage[0]
  CSRFToken.update newPage[2] if newPage[2]?
  removeNoscriptTags()
  executeScriptTags() if newPage[3]
  currentState = window.history.state
  triggerEvent 'page:change'

executeScriptTags = ->
  #scripts = Array::slice.call document.body.getElementsByTagName 'script'
  #for script in scripts when script.type in ['', 'text/javascript']
    #copy = document.createElement 'script'
    #copy.setAttribute attr.name, attr.value for attr in script.attributes
    #copy.appendChild document.createTextNode script.innerHTML
    #{ parentNode, nextSibling } = script
    #parentNode.removeChild script
    #parentNode.insertBefore copy, nextSibling
  #return

removeNoscriptTags = ->
  noscriptTags = Array::slice.call document.body.getElementsByTagName 'noscript'
  noscript.parentNode.removeChild noscript for noscript in noscriptTags
  return

reflectNewUrl = (url) ->
  if url isnt document.location.href
    referer = document.location.href
    window.history.pushState { turbolinks: true, position: currentState.position + 1 }, '', url

reflectRedirectedUrl = (xhr) ->
  if (location = xhr.getResponseHeader 'X-XHR-Current-Location') and location isnt document.location.pathname + document.location.search
    window.history.replaceState currentState, '', location + document.location.hash

rememberCurrentUrl = ->
  window.history.replaceState { turbolinks: true, position: Date.now() }, '', document.location.href

rememberCurrentState = ->
  currentState = window.history.state

rememberInitialPage = ->
  unless initialized
    rememberCurrentUrl()
    rememberCurrentState()
    createDocument = browserCompatibleDocumentParser()
    initialized = true

recallScrollPosition = (page) ->
  window.scrollTo page.positionX, page.positionY

resetScrollPosition = ->
  window.scrollTo 0, 0

removeHash = (url) ->
  link = url
  unless url.href?
    link = document.createElement 'A'
    link.href = url
  link.href.replace link.hash, ''

triggerEvent = (name) ->
  event = document.createEvent 'Events'
  event.initEvent name, true, true
  document.dispatchEvent event


invalidContent = (xhr) ->
  !xhr.getResponseHeader('Content-Type').match /^(?:text\/html|application\/xhtml\+xml|application\/xml)(?:;|$)/

extractTrackAssets = (doc) ->
  (node.src || node.href) for node in doc.head.childNodes when node.getAttribute?('data-turbolinks-track')?

assetsChanged = (doc) ->
  loadedAssets ||= extractTrackAssets document
  fetchedAssets  = extractTrackAssets doc
  fetchedAssets.length isnt loadedAssets.length or intersection(fetchedAssets, loadedAssets).length isnt loadedAssets.length

intersection = (a, b) ->
  [a, b] = [b, a] if a.length > b.length
  value for value in a when value in b

extractTitleAndBody = (doc) ->
  title = doc.querySelector 'title'
  [ title?.textContent, doc.body, CSRFToken.get(doc).token, 'runScripts' ]

CSRFToken =
  get: (doc = document) ->
    node:   tag = doc.querySelector 'meta[name="csrf-token"]'
    token:  tag?.getAttribute? 'content'
    
  update: (latest) ->
    current = @get()
    if current.token? and latest? and current.token isnt latest
      current.node.setAttribute 'content', latest
      
browserCompatibleDocumentParser = ->
  createDocumentUsingParser = (html) ->
    (new DOMParser).parseFromString html, 'text/html'

  createDocumentUsingDOM = (html) ->
    doc = document.implementation.createHTMLDocument ''
    doc.documentElement.innerHTML = html
    doc

  createDocumentUsingWrite = (html) ->
    doc = document.implementation.createHTMLDocument ''
    doc.open 'replace'
    doc.write html
    doc.close()
    doc

  # Use createDocumentUsingParser if DOMParser is defined and natively
  # supports 'text/html' parsing (Firefox 12+, IE 10)
  #
  # Use createDocumentUsingDOM if createDocumentUsingParser throws an exception
  # due to unsupported type 'text/html' (Firefox < 12, Opera)
  #
  # Use createDocumentUsingWrite if:
  #  - DOMParser isn't defined
  #  - createDocumentUsingParser returns null due to unsupported type 'text/html' (Chrome, Safari)
  #  - createDocumentUsingDOM doesn't create a valid HTML document (safeguarding against potential edge cases)
  try
    if window.DOMParser
      testDoc = createDocumentUsingParser '<html><body><p>test'
      createDocumentUsingParser
  catch e
    testDoc = createDocumentUsingDOM '<html><body><p>test'
    createDocumentUsingDOM
  finally
    unless testDoc?.body?.childNodes.length is 1
      return createDocumentUsingWrite

installClickHandlerLast = (event) ->
  unless event.defaultPrevented
    document.removeEventListener 'click', handleClick, false
    document.addEventListener 'click', handleClick, false

handleClick = (event) ->
  unless event.defaultPrevented
    link = extractLink event
    if link.nodeName is 'A' and !ignoreClick(event, link)
      visit link.href
      event.preventDefault()

extractLink = (event) ->
  link = event.target
  link = link.parentNode until !link.parentNode or link.nodeName is 'A'
  link

crossOriginLink = (link) ->
  location.protocol isnt link.protocol or location.host isnt link.host

anchoredLink = (link) ->
  ((link.hash and removeHash(link)) is removeHash(location)) or
    (link.href is location.href + '#')

nonHtmlLink = (link) ->
  url = removeHash link
  url.match(/\.[a-z]+(\?.*)?$/g) and not url.match(/\.html?(\?.*)?$/g)

noTurbolink = (link) ->
  until ignore or link is document
    ignore = link.getAttribute('data-no-turbolink')?
    link = link.parentNode
  ignore

targetLink = (link) ->
  link.target.length isnt 0

nonStandardClick = (event) ->
  event.which > 1 or event.metaKey or event.ctrlKey or event.shiftKey or event.altKey

ignoreClick = (event, link) ->
  crossOriginLink(link) or anchoredLink(link) or nonHtmlLink(link) or noTurbolink(link) or targetLink(link) or nonStandardClick(event)

initializeTurbolinks = ->
  document.addEventListener 'click', installClickHandlerLast, true
  document.addEventListener 'page:prefetched', logPrefetchCompletion, true
  window.addEventListener 'popstate', (event) ->
    fetchHistory event.state if event.state?.turbolinks
  , false

browserSupportsPushState =
  window.history and window.history.pushState and window.history.replaceState and window.history.state != undefined

browserIsntBuggy =
  !navigator.userAgent.match /CriOS\//

requestMethodIsSafe =
  requestMethod in ['GET','']

initializeTurbolinks() if browserSupportsPushState and browserIsntBuggy and requestMethodIsSafe

# Call Turbolinks.visit(url) from client code
@Turbolinks = { visit, prefetchPages }
