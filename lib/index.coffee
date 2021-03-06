exec = require("child_process").exec
path = require "path"
fs = require "fs"
Q = require "q"
_ = require "underscore"
uslug = require "uslug"
ejs = require "ejs"
cheerio = require "cheerio"
request = require "superagent"
fsextra = require "fs-extra"
removeDiacritics = require("diacritics").remove
mime = require "mime"

uuid = ->
  'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace /[xy]/g, (c)->
    r = Math.random()*16|0
    return (if c is 'x' then r else r&0x3|0x8).toString(16)

class EPub
  constructor: (options, output)->
    @options = options
    self = @
    @defer = new Q.defer()

    if output
      @options.output = output

    if not @options.output
      console.error(new Error("No Output Path"))
      @defer.reject(new Error("No output path"))
      return false

    if not options.title or not options.content
      console.log "options not valid"
      return false

    @options = _.extend {
      description: options.title
      publisher: "anonymous"
      author: ["anonymous"]
      tocTitle: "Table Of Contents"
      appendChapterTitles: true
      date: new Date().toISOString()
      lang: "en"
      fonts: []
      customOpfTemplatePath: null
      customNcxTocTemplatePath: null
      customHtmlTocTemplatePath: null
      version: 3
    }, options

    if @options.version is 2
      @options.docHeader = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" lang="#{self.options.lang}">
"""
    else
      @options.docHeader = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" lang="#{self.options.lang}">
"""

    if _.isString @options.author
      @options.author = [@options.author]
    if _.isEmpty @options.author
      @options.author = ["anonymous"]
    if not @options.tempDir
      @options.tempDir = path.resolve __dirname, "../tempDir/"
    @id = uuid()
    @uuid = path.resolve @options.tempDir, @id
    @options.uuid = @uuid
    @options.id = @id
    @options.images = []
    @options.content = _.map @options.content, (content, index)->
      titleSlug = uslug removeDiacritics content.title || "no title"
      content.filePath = path.resolve self.uuid, "./OEBPS/#{index}_#{titleSlug}.xhtml"
      content.href = "#{index}_#{titleSlug}.xhtml"
      content.id = "item_#{index}"
      content.dir = path.dirname(content.path)

      #fix Author Array
      content.author =
        if content.author and _.isString content.author then [content.author]
        else if not content.author or not _.isArray content.author then []
        else content.author

      # Only body innerHTML is allowed
      #reg = /<body[^>]*>((.|[\n\r])*)<\/body>/
      #content.data = content.data.match(reg)?[1] || content.data
      ## replace with cheerio
      allowedAttributes = ["content", "alt" ,"id","title", "src", "href", "about", "accesskey", "aria-activedescendant", "aria-atomic", "aria-autocomplete", "aria-busy", "aria-checked", "aria-controls", "aria-describedat", "aria-describedby", "aria-disabled", "aria-dropeffect", "aria-expanded", "aria-flowto", "aria-grabbed", "aria-haspopup", "aria-hidden", "aria-invalid", "aria-label", "aria-labelledby", "aria-level", "aria-live", "aria-multiline", "aria-multiselectable", "aria-orientation", "aria-owns", "aria-posinset", "aria-pressed", "aria-readonly", "aria-relevant", "aria-required", "aria-selected", "aria-setsize", "aria-sort", "aria-valuemax", "aria-valuemin", "aria-valuenow", "aria-valuetext", "class", "content", "contenteditable", "contextmenu", "datatype", "dir", "draggable", "dropzone", "hidden", "hreflang", "id", "inlist", "itemid", "itemref", "itemscope", "itemtype", "lang", "media", "ns1:type", "ns2:alphabet", "ns2:ph", "onabort", "onblur", "oncanplay", "oncanplaythrough", "onchange", "onclick", "oncontextmenu", "ondblclick", "ondrag", "ondragend", "ondragenter", "ondragleave", "ondragover", "ondragstart", "ondrop", "ondurationchange", "onemptied", "onended", "onerror", "onfocus", "oninput", "oninvalid", "onkeydown", "onkeypress", "onkeyup", "onload", "onloadeddata", "onloadedmetadata", "onloadstart", "onmousedown", "onmousemove", "onmouseout", "onmouseover", "onmouseup", "onmousewheel", "onpause", "onplay", "onplaying", "onprogress", "onratechange", "onreadystatechange", "onreset", "onscroll", "onseeked", "onseeking", "onselect", "onshow", "onstalled", "onsubmit", "onsuspend", "ontimeupdate", "onvolumechange", "onwaiting", "prefix", "property", "rel", "resource", "rev", "role", "spellcheck", "style", "tabindex", "target", "title", "type", "typeof", "vocab", "xml:base", "xml:lang", "xml:space"]
      allowedXhtml11Tags = ["div", "p", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "dl", "dt", "dd", "address", "hr", "pre", "blockquote", "center", "ins", "del", "a", "span", "bdo", "br", "em", "strong", "dfn", "code", "samp", "kbd", "bar", "cite", "abbr", "acronym", "q", "sub", "sup", "tt", "i", "b", "big", "small", "u", "s", "strike", "basefont", "font", "object", "param", "img", "table", "caption", "colgroup", "col", "thead", "tfoot", "tbody", "tr", "th", "td", "embed", "applet", "iframe", "img", "map", "noscript", "ns:svg", "object", "script", "table", "tt", "var"]
      content.data = content.data.replace(/\&/g, "&amp;")
      $ = cheerio.load content.data, {xmlMode: true, lowerCaseTags: true, ignoreWhitespace: true, recognizeSelfClosing: true}
      if $("body").length
        $ = cheerio.load $("body").html(), {xmlMode: true, lowerCaseTags: true, ignoreWhitespace: true, recognizeSelfClosing: true}
      $($("*").get().reverse()).each (elemIndex, elem)->
        attrs = elem.attribs
        that = @
        if that.name in ["img", "br", "hr"]
          $(that).text("")
          if that.name is "img"
            $(that).attr("alt", $(that).attr("alt") or "image-placeholder")

        for k,v of attrs
          if k in allowedAttributes
            if k is "type"
              if that.name isnt "script"
                $(that).removeAttr(k)
          else
            $(that).removeAttr(k)
        if self.options.version is 2
          if that.name in allowedXhtml11Tags
          else
            console.log "Warning (content[" + index + "]):", that.name, "tag isn't allowed on EPUB 2/XHTML 1.1 DTD."
            child = $(that).html()
            $(that).replaceWith($("<div>" + child + "</div>"))

      $("img").each (index, elem)->
        url = $(elem).attr("src")
        id = uuid()
        mediaType = mime.lookup url
        extension = mime.extension mediaType
        $(elem).attr("src", "images/#{id}.#{extension}")
        dir = content.dir
        self.options.images.push {id, url, dir, mediaType, extension}
      content.data = $.xml()
      content

    if @options.cover
      @options._coverMediaType = mime.lookup @options.cover
      @options._coverExtension = mime.extension @options._coverMediaType

    @render()
    @promise = @defer.promise
    @

  render: ()->
    self = @
    console.log("Generating Template Files.....")
    @generateTempFile().then ()->
      console.log("Downloading Images...")
      self.downloadAllImage().fin ()->
        console.log("Making Cover...")
        self.makeCover().then ()->
          console.log("Generating Epub Files...")
          self.genEpub().then (result)->
            console.log("About to finish...")
            self.defer.resolve(result)
            console.log("Done.")
          , (err)->
            self.defer.reject(err)
        , (err)->
          self.defer.reject(err)
      , (err)->
        self.defer.reject(err)
    , (err)->
      self.defer.reject(err)

  generateTempFile: ()->
    generateDefer = new Q.defer()
    self = @
    if !fs.existsSync(@options.tempDir)
      fs.mkdirSync(@options.tempDir)
    fs.mkdirSync @uuid
    fs.mkdirSync path.resolve(@uuid, "./OEBPS")
    @options.css ||= ".epub-author{color: #555;}.epub-link{margin-bottom: 30px;}.epub-link a{color: #666;font-size: 90%;}.toc-author{font-size: 90%;color: #555;}.toc-link{color: #999;font-size: 85%;display: block;}hr{border: 0;border-bottom: 1px solid #dedede;margin: 60px 10%;}"
    fs.writeFileSync path.resolve(@uuid, "./OEBPS/style.css"), @options.css
    if self.options.fonts.length
      fs.mkdirSync(path.resolve @uuid, "./OEBPS/fonts")
      @options.fonts = _.map @options.fonts, (font)->
        if !fs.existsSync(font)
          generateDefer.reject(new Error('Custom font not found at ' + font + '.'))
          return generateDefer.promise
        filename = path.basename(font)
        fsextra.copySync(font, path.resolve self.uuid, "./OEBPS/fonts/" + filename)
        filename
    fs.mkdirSync(path.resolve @uuid, "./OEBPS/images")
    _.each @options.content, (content)->
      data = """#{self.options.docHeader}
        <head>
        <meta charset="UTF-8" />
        <title>#{content.title}</title>
        <link rel="stylesheet" type="text/css" href="style.css" />
        </head>
      <body>
      """
      data += if content.title and self.options.appendChapterTitles then "<h1>#{content.title}</h1>" else ""
      data += if content.title and content.author and content.author.length then "<p class='epub-author'>#{content.author.join(", ")}</p>" else ""
      data += if content.title and content.url then "<p class='epub-link'><a href='#{content.url}'>#{content.url}</a></p>" else ""
      data += "#{content.data}</body></html>"
      fs.writeFileSync(content.filePath, data)

    # write mimetype file
    fs.writeFileSync(@uuid + "/mimetype", "application/epub+zip")

    # write meta-inf/container.xml
    fs.mkdirSync(@uuid + "/META-INF")
    fs.writeFileSync( "#{@uuid}/META-INF/container.xml", """<?xml version="1.0" encoding="UTF-8" ?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>""")

    if self.options.version is 2
      # write meta-inf/com.apple.ibooks.display-options.xml [from pedrosanta:xhtml#6]
      fs.writeFileSync "#{@uuid}/META-INF/com.apple.ibooks.display-options.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <display_options>
          <platform name="*">
            <option name="specified-fonts">true</option>
          </platform>
        </display_options>
      """

    opfPath = self.options.customOpfTemplatePath or path.resolve(__dirname, "../templates/epub#{self.options.version}/content.opf.ejs")
    if !fs.existsSync(opfPath)
      generateDefer.reject(new Error('Custom file to OPF template not found.'))
      return generateDefer.promise

    ncxTocPath = self.options.customNcxTocTemplatePath or path.resolve(__dirname , "../templates/toc.ncx.ejs" )
    if !fs.existsSync(ncxTocPath)
      generateDefer.reject(new Error('Custom file the NCX toc template not found.'))
      return generateDefer.promise

    htmlTocPath = self.options.customHtmlTocTemplatePath or path.resolve(__dirname, "../templates/epub#{self.options.version}/toc.xhtml.ejs")
    if !fs.existsSync(htmlTocPath)
      generateDefer.reject(new Error('Custom file to HTML toc template not found.'))
      return generateDefer.promise

    Q.all([
      Q.nfcall ejs.renderFile, opfPath, self.options
      Q.nfcall ejs.renderFile, ncxTocPath, self.options
      Q.nfcall ejs.renderFile, htmlTocPath, self.options
    ]).spread (data1, data2, data3)->
      fs.writeFileSync(path.resolve(self.uuid , "./OEBPS/content.opf"), data1)
      fs.writeFileSync(path.resolve(self.uuid , "./OEBPS/toc.ncx"), data2)
      fs.writeFileSync(path.resolve(self.uuid, "./OEBPS/toc.xhtml"), data3)
      generateDefer.resolve()
    , (err)->
      console.error arguments
      generateDefer.reject(err)

    generateDefer.promise

  makeCover: ()->
    userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_2) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/34.0.1847.116 Safari/537.36"
    coverDefer = new Q.defer()
    if @options.cover
      destPath = path.resolve @uuid, ("./OEBPS/cover." + @options._coverExtension)
      writeStream = null
      if @options.cover.slice(0,4) is "http"
        writeStream = request.get(@options.cover).set 'User-Agent': userAgent
        writeStream.pipe(fs.createWriteStream(destPath))
      else
        writeStream = fs.createReadStream(@options.cover)
        writeStream.pipe(fs.createWriteStream(destPath))

      writeStream.on "end", ()->
        console.log "[Success] cover image downloaded successfully!"
        coverDefer.resolve()
      writeStream.on "error", (err)->
        console.log "Error", err
        console.log arguments
        coverDefer.reject(err)
    else
      coverDefer.resolve()

    coverDefer.promise


  downloadImage: (options)->  #{id, url, mediaType}
    self = @
    userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_2) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/34.0.1847.116 Safari/537.36"
    if not options.url and typeof options isnt "string"
      return false
    downloadImageDefer = new Q.defer()
    filename = path.resolve self.uuid, ("./OEBPS/images/" + options.id + "." + options.extension)
    if options.url.indexOf("file://") == 0
      auxpath = options.url.substr(7)
      fsextra.copySync(auxpath,filename)
      return downloadImageDefer.resolve(options)
    else
      if options.url.indexOf("http") is 0
        requestAction = request.get(options.url).set 'User-Agent': userAgent
        requestAction.pipe(fs.createWriteStream(filename))
      else
        requestAction = fs.createReadStream(path.resolve(options.dir, options.url))
        requestAction.pipe(fs.createWriteStream(filename))
      requestAction.on 'error', (err)->
        console.error '[Download Error]' ,'Error while downloading', options.url, err
        fs.unlinkSync(filename)
        downloadImageDefer.reject(err)

      requestAction.on 'end', ()->
        console.log "[Download Success]", options.url
        downloadImageDefer.resolve(options)

      downloadImageDefer.promise


  downloadAllImage: ()->
    self = @
    imgDefer = new Q.defer()
    if not self.options.images.length
      imgDefer.resolve()
    else
      deferArray = []
      _.each self.options.images, (image)->
        deferArray.push self.downloadImage(image)
      Q.all deferArray
      .fin ()->
        imgDefer.resolve()
    imgDefer.promise


  runCommand: (cmd, option)->
    defer = new Q.defer()
    exec cmd, option, (err, stderr, stdout)->
      if err
        console.error(cmd, stderr, stdout)
        defer.reject(err)
        return false
      if stderr
        console.warn stderr
      if stdout and option.quite
        console.log stdout
      defer.resolve stdout
    defer.promise


  genEpub: ()->
    # Thanks to Paul Bradley
    # http://www.bradleymedia.org/gzip-markdown-epub/

    genDefer = new Q.defer()

    self = @
    filename = "book.epub.zip"
    initCmd = "zip -q -X -0 #{filename} mimetype"
    zipCmd  = "zip -q -X -9 -r #{filename} * -x mimetype #{filename}"
    cleanUp = "mv #{filename} book.epub && rm -f -r META-INF OEBPS mimetype"
    cleanUp = "mv #{filename} book.epub"
    cwd = @uuid
    self.runCommand(initCmd, {cwd}).then ()->
      self.runCommand(zipCmd, {cwd}).then ()->
        self.runCommand(cleanUp, {cwd}).then ()->
          stream = fs.createReadStream( path.resolve self.uuid, "book.epub" )
          stream.pipe fs.createWriteStream self.options.output
          stream.on "error", (err)->
            console.error(err)
            self.defer.reject(err)
          stream.on "end", ()->
            self.defer.resolve()
            currentDir = self.options.tempDir
            self.runCommand("rm -f -r #{self.id}/", {cwd: currentDir})
        , (err)->
          genDefer.reject(err)
      , (err)->
        genDefer.reject(err)
    , (err)->
      genDefer.reject(err)

    genDefer.promise

module.exports = EPub