#' GeoNetwork REST API Manager
#'
#' @docType class
#' @importFrom R6 R6Class
#' @importFrom openssl base64_encode
#' @import httr
#' @import XML
#' @importFrom openssl base64_encode
#' @import keyring
#' @import geometa
#' 
#' @export
#' @keywords geonetwork rest api
#' @return Object of \code{\link{R6Class}} with methods for communication with
#' the REST API of a GeoNetwork instance.
#' @format \code{\link{R6Class}} object.
#' 
#' @examples
#' \dontrun{
#'    GMManager$new("http://localhost:8080/geonetwork", "admin", "geonetwork")
#' }
#'
#' @field loggerType the type of logger
#' @field verbose.info if geosapi logs have to be printed
#' @field verbose.debug if curl logs have to be printed
#' @field url the Base url of GeoNetwork
#' @field version the version of GeoNetwork. Handled as \code{GNVersion} object
#' @field user the user name
#'
#' @section Methods:
#' \describe{
#'  \item{\code{new(url, user, pwd, version, logger)}}{
#'    This method is used to instantiate a GNManager with the \code{url} of the
#'    GeoNetwork and credentials to authenticate (\code{user}/\code{pwd}). By default,
#'    the \code{logger} argument will be set to \code{NULL} (no logger). This argument
#'    accepts two possible values: \code{INFO}: to print only geonapi logs,
#'    \code{DEBUG}: to print geonapi and CURL logs
#'  }
#'  \item{\code{logger(type, text)}}{
#'    Basic logger to report geonapi logs. Used internally
#'  }
#'  \item{\code{INFO(text)}}{
#'    Logger to report information. Used internally
#'  }
#'  \item{\code{WARN(text)}}{
#'    Logger to report warnings. Used internally
#'  }
#'  \item{\code{ERROR(text)}}{
#'    Logger to report errors. Used internally
#'  }
#'  \item{\code{getUrl()}}{
#'    Get the authentication URL
#'  }
#'  \item{\code{getLang()}}{
#'    Get the service lang
#'  }
#'  \item{\code{login(user, pwd)}}{
#'    This methods attempts a connection to GeoNetwork REST API. User internally
#'    during initialization of \code{GNManager}.
#'  }
#'  \item{\code{getCookies()}}{
#'    Get user session cookies
#'  }
#'  \item{\code{getToken()}}{
#'    Get user session token
#'  }
#'  \item{\code{getClassName()}}{
#'    Retrieves the name of the class instance
#'  }
#'  \item{\code{getGroups()}}{
#'    Retrives the list of user groups available in Geonetwork
#'  }
#'  \item{\code{insertMetadata(xml, file, geometa, group, category, stylesheet, validate, geometa_validate, geometa_inspire)}}{
#'    Inserts a metadata by file, XML object or \pkg{geometa} object of class
#'    \code{ISOMetadata} or \code{ISOFeatureCatalogue}. If successful, returns the Geonetwork
#'    metadata internal identifier (integer). Extra parameters \code{geometa_validate} (TRUE 
#'    by default) and \code{geometa_inspire} (FALSE by default) can be used with geometa objects 
#'    for perform ISO and INSPIRE validation respectively.
#'  }
#'  \item{\code{setPrivConfiguration(id, config)}}{
#'    Set the privilege configuration for a metadata. 'id' is the metadata integer id.
#'    'config' is an object of class "GNPrivConfiguration".
#'  }
#'  \item{\code{get(id, by, output)}}{
#'    Generic getter for metadata. Possible values for by are 'id', 'uuid'. Used
#'    internally only. The 'output' argument gives the type of output to return,
#'    with possible values "id", "metadata", "info".
#'  }
#'  \item{\code{getMetadataByID(id)}}{
#'    Get a metadata by Id. Returns an object of class \code{ISOMetadata} (ISO 19115)
#'    or \code{ISOFeatureCatalogue} (ISO 19110) (from \pkg{geometa} package)
#'  }
#'  \item{\code{getMetadataByUUID(uuid)}}{
#'    Get a metadata by UUID. Returns an object of class \code{ISOMetadata} (ISO 19115)
#'    or \code{ISOFeatureCatalogue} (ISO 19110) (from \pkg{geometa} package)
#'  }
#'  \item{\code{getInfoByID(id)}}{
#'    Get a metadata Info by Id. Returns an XML document object
#'  }
#'  \item{\code{getInfoByUUID(uuid)}}{
#'    Get a metadata Info by UUID. Returns an XML document object
#'  }
#'  \item{\code{updateMetadata(id, xml, file, geometa, geometa_validate, geometa_inspire)}}{
#'    Updates a metadata by file, XML object or \pkg{geometa} object of class
#'    'ISOMetadata' or 'ISOFeatureCatalogue'. Extra parameters \code{geometa_validate} (TRUE 
#'    by default) and \code{geometa_inspire} (FALSE by default) can be used with geometa objects 
#'    for perform ISO and INSPIRE validation respectively.
#'  }
#'  \item{\code{deleteMetadata(id)}}{
#'    Deletes a metadata
#'  }
#'  \item{\code{deleteMetadataAll()}}{
#'    Deletes all metadata for which the authenticated user is owner
#'  }
#' }
#' 
#' @author Emmanuel Blondel <emmanuel.blondel1@@gmail.com>
GNManager <- R6Class("GNManager",
  lock_objects = FALSE,
  
  #TODO provider specific formatter to prevent these fields to be printable
  private = list(
    keyring_service = NULL,
    user = NULL,
    token = NULL,
    cookies = NULL,
    
    #getEditingMetadataVersion
    #---------------------------------------------------------------------------
    getEditingMetadataVersion = function(id){
      self$INFO(sprintf("Fetching metadata version for id = %s", id))
      version <- NULL
      req <- GNUtils$GET(
        url = self$getUrl(),
        path = "/metadata.edit!",
        token = private$token,
        query = list(id = id),
        verbose = self$verbose.debug
      )
      xml <- NULL
      if(status_code(req) == 200){
        self$INFO("Successfully fetched editing metadata!")
        xml <- GNUtils$parseResponseXML(req)
        versionXML <- getNodeSet(xml, "//geonet:info/version",
                                 c(geonet = "http://www.fao.org/geonetwork"))
        if(length(versionXML)>0){
          version <- as.integer(xmlValue(versionXML[[1]]))
        }else{
          stop("No geonet:info XML element found")
        }
      }else{
        self$ERROR(sprintf("Error while fetching metadata version - %s", message_for_status(status_code(req))))
        self$ERROR(content(req))
      }
      
      return(version)
    }
  ),
                     
  public = list(
    #logger
    verbose.info = FALSE,
    verbose.debug = FALSE,
    loggerType = NULL,
    logger = function(type, text){
      if(self$verbose.info){
        cat(sprintf("[geonapi][%s] %s \n", type, text))
      }
    },
    INFO = function(text){self$logger("INFO", text)},
    WARN = function(text){self$logger("WARN", text)},
    ERROR = function(text){self$logger("ERROR", text)},
    
    #manager
    url = NA,
    version = NULL,
    basicAuth = FALSE,
    initialize = function(url, user = NULL, pwd = NULL, version, logger = NULL){
      
      #logger
      if(!missing(logger)){
        if(!is.null(logger)){
          self$loggerType <- toupper(logger)
          if(!(self$loggerType %in% c("INFO","DEBUG"))){
            stop(sprintf("Unknown logger type '%s", logger))
          }
          if(self$loggerType == "INFO"){
            self$verbose.info = TRUE
          }else if(self$loggerType == "DEBUG"){
            self$verbose.info = TRUE
            self$verbose.debug = TRUE
          }
        }
      }
      
      #GN version
      if(!is(version, "character")) stop("The version should be an object of class 'character'")
      self$version <- GNVersion$new(version = version)
      
      #service lang
      isGN26 <- self$version$value$major == 2 && self$version$value$minor == 6
      self$lang <- ifelse(isGN26,"en","eng")
      
      #basic auth
      self$basicAuth <- self$version$value$major == 3
      
      #baseUrl
      self$url = sprintf("%s/srv/%s", url, self$lang)
      private$keyring_service <- paste0("geonapi@", url)
      
      #try to login
      if(!is.null(user) && !is.null(pwd)){        
        self$INFO(sprintf("Connecting to GeoNetwork services as authenticated user '%s'", user))
        self$login(user, pwd)
      }else{
        self$INFO("Connected to GeoNetwork services as anonymous user")
      }
      
      
      invisible(self)
    },
    
    #getUrl
    #---------------------------------------------------------------------------
    getUrl = function(){
      return(self$url)
    },
    
    #getLang
    #---------------------------------------------------------------------------
    getLang = function(){
      return(self$lang)
    },
    
    #login
    #---------------------------------------------------------------------------
    login = function(user, pwd){
      
      req <- NULL
      if(self$basicAuth){
        #for newer versions >= 3
        req <- GNUtils$POST(
          url = self$getUrl(), path = "/info?type=me",
          user = user, pwd = pwd, content = NULL, contentType = NULL,
          verbose = TRUE 
        )
      }else{
        #for older versions < 3
        gnRequest <- GNRESTRequest$new(username = user, password = pwd)
        req <- GNUtils$POST(
          url = self$getUrl(),
          path = "/xml.user.login",
          content = gnRequest$encode(),
          contentType = "text/xml",
          verbose = self$verbose.debug
        )
      }
      
      private$user <- user
      keyring::key_set_with_value(private$keyring_service, username = user, password = pwd)
      
      req_cookies <- cookies(req)
      cookies <- as.list(req_cookies$value)
      names(cookies) <- req_cookies$name
      if(length(cookies[names(cookies)=="XSRF-TOKEN"])>0){
        private$token <- cookies[names(cookies)=="XSRF-TOKEN"][[1]]
      }
      cookies <- unlist(cookies[names(cookies)!="XSRF-TOKEN"])
      private$cookies <- paste0(sapply(names(cookies), function(cookiename){paste0(cookiename,"=",cookies[[cookiename]])}),collapse=";")
      
      if(!is.null(private$token)){
        req <- GNUtils$POST(
          url = self$getUrl(), path = "/info?type=me",
          user = user, pwd = pwd, token = private$token, cookies = private$cookies, content = NULL, contentType = NULL,
          verbose = TRUE 
        )
      }
      
      if(status_code(req) == 401){
        err <- "Impossible to login to GeoNetwork: Wrong credentials"
        self$ERROR(err)
        stop(err)
      }
      if(status_code(req) == 404){
        err <- "Impossible to login to GeoNetwork: Incorrect URL or GeoNetwork temporarily unavailable"
        self$ERROR(err)
        stop(err)
      }
      if(status_code(req) != 200){
        err <- "Impossible to login to GeoNetwork: Unexpected error"
        self$ERROR(err)
        stop(err)
      }
      
      if(status_code(req) == 200){
        self$INFO("Successfully authenticated to GeoNetwork!\n")
      }
      return(TRUE)
    },
    
    getCookies = function(){
      return(private$cookies)
    },
    
    getToken = function(){
      return(private$token)
    },
    
    #getClassName
    #---------------------------------------------------------------------------
    getClassName = function(){
      return(class(self)[1])
    },
    
    #getGroups
    #---------------------------------------------------------------------------
    getGroups = function(){
      out <- NULL
      self$INFO("Getting user groups...")
      req <- GNUtils$GET(
        url = self$getUrl(),
        path = "/xml.info",
        token = private$token, cookies = private$cookies,
        user = private$user, 
        pwd = keyring::key_get(private$keyring_service, username = private$user),
        query = list(type = "groups"),
        verbose = self$verbose.debug
      )
      if(status_code(req) == 200){
        self$INFO("Successfully fetched user groups!")
        xml <- GNUtils$parseResponseXML(req, "UTF-8")
        xml.groups <- getNodeSet(xml, "//group/group")
        out <- do.call("rbind", lapply(xml.groups, function(xml.group){
          out.group <- data.frame(
            id = xmlGetAttr(xml.group, "id"),
            name = xmlValue(xmlChildren(xml.group)$name),
            stringsAsFactors = FALSE
          )
          return(out.group)
        }))
      }else{
        self$ERROR("Error while fetching user groups")
      }
      return(out)
    },
    
    #insertMetadata
    #---------------------------------------------------------------------------
    insertMetadata = function(xml = NULL, file = NULL, geometa = NULL, group,
                              category = NULL, stylesheet = NULL, validate = FALSE,
                              geometa_validate = TRUE, geometa_inspire = FALSE){
      self$INFO("Inserting metadata ...")
      out <- NULL
      data <- NULL
      isTempFile <- FALSE
      if(!is.null(xml)){
        tempf = tempfile(tmpdir = tempdir())
        file <- paste(tempf,".xml",sep='')
        isTempFile <- TRUE
        saveXML(xml, file, encoding = "UTF-8")
      }
      if(!is.null(file)){
        data <- geometa::readISO19139(file = file, raw = TRUE)
        if(isTempFile) unlink(file)
      }
      if(!is.null(geometa)){
        if(!is(geometa, "ISOMetadata") & !is(geometa, "ISOFeatureCatalogue")){
          stop("Object 'geometa' should be of class 'ISOMetadata' or 'ISOFeatureCatalogue")
        }
        data <- geometa$encode(validate = geometa_validate, inspire = geometa_inspire)
      }
      
      if(is.null(data)){
        stop("At least one of 'file', 'xml', or 'geometa' argument is required!")
      }
      
      if(is.null(category)) category <- "_none_"
      if(is.null(stylesheet)) stylesheet <- "_none_"
      gnRequest <- GNRESTRequest$new(
        data = data,
        group = group,
        category = category,
        stylesheet = stylesheet,
        validate = ifelse(validate, "on", "off")
      )

      req <- GNUtils$POST(
        url = self$getUrl(),
        path = "/xml.metadata.insert",
        token = private$token, cookies = private$cookies,
        user = private$user, 
        pwd = keyring::key_get(private$keyring_service, username = private$user),
        content = gnRequest$encode(),
        contentType = "text/xml",
        verbose = self$verbose.debug
      )
      if(status_code(req) == 200){
        self$INFO("Successfully inserted metadata!")
        response <- GNUtils$parseResponseXML(req)
        out <- as.integer(xpathApply(response, "//id", xmlValue)[[1]])
      }else{
        self$ERROR(sprintf("Error while inserting metadata - %s", message_for_status(status_code(req))))
        self$ERROR(content(req))
      }
      return(out)
    },
    
    #setPrivConfiguration
    #---------------------------------------------------------------------------
    setPrivConfiguration = function(id, config){
      self$INFO(sprintf("Setting privileges for metadata id = %s", id))
      out <- FALSE
      if(!is(config, "GNPrivConfiguration")){
        stop("The 'config' value should be an object of class 'GNPrivConfiguration")
      }
      queryPrivParams = list()
      for(grant in config$privileges){
        for(priv in grant$privileges){
          el <- paste0("_", grant$group, "_", priv)
          queryPrivParams[[el]] <- "on"
        }
      }
      queryParams <- list()
      if(self$version$value$major == 3){
        queryParams <- c(list("_content_type" = "xml"), queryPrivParams, list(id = id))
      }else{
        queryParams <- c(list(id = id), queryPrivParams)
      }

      req <- GNUtils$GET(
        url = self$getUrl(),
        path = ifelse(self$version$value$major < 3, "/metadata.admin", "md.privileges.update"),
        token = private$token, cookies = private$cookies,
        user = private$user,
        pwd = keyring::key_get(private$keyring_service, username = private$user),
        query = queryParams,
        verbose = self$verbose.debug
      )
      if(status_code(req) == 200){
        self$INFO(sprintf("Successfully set privileges for metadata id = %s!", id))
        out <- TRUE
      }else{
        self$ERROR(sprintf("Error while setting privileges - %s", message_for_status(status_code(req))))
        self$ERROR(content(req))
      }
      return(out)
    },
    
    
    #get
    #---------------------------------------------------------------------------
    get = function(id, by, output){
      allowedByValues <- c("id","uuid")
      if(!(by %in% allowedByValues)){
        stop(sprintf("Unsupported 'by' parameter value '%s'. Possible values are [%s]",
                     by, paste0(allowedByValues, collapse=",")))
      }
      allowedOutputTypes <- c("id", "metadata", "info")
      if(!(output %in% allowedOutputTypes)){
        stop(sprintf("Unsupported 'output' type '%s'. Possible values are [%s]",
                     output, paste0(allowedOutputTypes, collapse=",")))
      }
      self$INFO(sprintf("Fetching metadata for %s = %s", by, id))
      out <- NULL
      if(by=="id"){
        gnRequest <- GNRESTRequest$new(id = id)
      }else if(by=="uuid"){
        gnRequest <- GNRESTRequest$new(uuid = id)
      }
      req <- GNUtils$POST(
        url = self$getUrl(),
        path = "/xml.metadata.get",
        token = private$token, cookies = private$cookies,
        user = private$user,
        pwd = keyring::key_get(private$keyring_service, username = private$user),
        content = gnRequest$encode(),
        contentType = "text/xml",
        verbose = self$verbose.debug
      )
      if(status_code(req) == 200){
        self$INFO("Successfully fetched metadata!")
        xml <- GNUtils$parseResponseXML(req, "UTF-8")
        if(output == "id"){
          self$INFO(sprintf("tralala"))
          idXML <- getNodeSet(xml, "//geonet:info/id", c(geonet = "http://www.fao.org/geonetwork"))
          self$INFO(sprintf(idXML))
          if(length(idXML)>0){
            out <- as.integer(xmlValue(idXML[[1]]))
          }else{
            stop("No geonet:info XML element found")
          }
        }else if(output == "metadata"){
          #bridge to geometa package once geometa XML decoding supported
          isoClass <- xmlName(xmlRoot(xml))
          out <- NULL
          if(isoClass=="MD_Metadata"){
            out <- geometa::ISOMetadata$new(xml = xml)
          }else if(isoClass=="FC_FeatureCatalogue"){
            out <- geometa::ISOFeatureCatalogue$new(xml = xml)
          }
        }else if(output == "info"){
          #TODO support for GNInfo object
          stop("GNInfo is not yet implemented in geonapi!")
        }
      }else{
        self$ERROR(sprintf("Error while fetching metadata - %s", message_for_status(status_code(req))))
        self$ERROR(content(req))
      }
      return(out)
    },
    
    #getMetadataByID
    #---------------------------------------------------------------------------
    getMetadataByID = function(id){
      return(self$get(id, by = "id", output = "metadata")) 
    },
    
    #getMetadataByUUID
    #---------------------------------------------------------------------------
    getMetadataByUUID = function(uuid){
      return(self$get(uuid, by = "uuid", output = "metadata")) 
    },
    
    #getInfoByID
    #---------------------------------------------------------------------------
    getInfoByID = function(id){
      return(self$get(id, by = "id", output = "info")) 
    },
    
    #getInfoByUUID
    #---------------------------------------------------------------------------
    getInfoByUUID = function(uuid){
      return(self$get(uuid, by = "uuid", output = "info")) 
    },
    
    #updateMetadata
    #---------------------------------------------------------------------------
    updateMetadata = function(id, xml = NULL, file = NULL, geometa = NULL,
                              geometa_validate = TRUE, geometa_inspire = FALSE){
      
      self$INFO(sprintf("Updating metadata id = %s ...", id))
      out <- NULL
      data <- NULL
      isTempFile <- FALSE
      if(!is.null(xml)){
        tempf = tempfile(tmpdir = tempdir())
        file <- paste(tempf,".xml",sep='')
        isTempFile <- TRUE
        saveXML(xml, file, encoding = "UTF-8")
      }
      if(!is.null(file)){
        data <- geometa::readISO19139(file = file, raw = TRUE)
        if(isTempFile) unlink(file)
      }
      if(!is.null(geometa)){
        if(!is(geometa, "ISOMetadata") & !is(geometa, "ISOFeatureCatalogue")){
          stop("Object 'geometa' should be of class 'ISOMetadata' or 'ISOFeatureCatalogue")
        }
        data <- geometa$encode(validate = geometa_validate, inspire = geometa_inspire)
      }
      
      if(is.null(data)){
        stop("At least one of 'file', 'xml', or 'geometa' argument is required!")
      }
      
      if(self$version$value$major >= 3){
        gnRequest <- GNRESTRequest$new(
          id = id,
          data = data
        )
      }else{
        gnRequest <- GNRESTRequest$new(
          id = id,
          version = private$getEditingMetadataVersion(id),
          data = data
        )
      }
      
      req <- GNUtils$POST(
        url = self$getUrl(),
        path = "/metadata.update.finish",
        token = private$token, cookies = private$cookies,
        user = private$user,
        pwd = keyring::key_get(private$keyring_service, username = private$user),
        content = gnRequest$encode(),
        contentType = "text/xml",
        verbose = self$verbose.debug
      )
      if(status_code(req) == 200){
        self$INFO("Successfully updated metadata!")
        response <- GNUtils$parseResponseXML(req)
        out <- as.integer(xpathApply(response, "//id", xmlValue)[[1]])
      }else{
        self$ERROR(sprintf("Error while updating metadata - %s", message_for_status(status_code(req))))
        self$ERROR(content(req))
      }
      return(out)
      
    },
    
    #deleteMetadata
    #---------------------------------------------------------------------------
    deleteMetadata = function(id){
      self$INFO(sprintf("Deleting metadata id = %s ...", id))
      out <- NULL
      gnRequest <- GNRESTRequest$new(id = id)
      req <- GNUtils$POST(
        url = self$getUrl(),
        path = "/xml.metadata.delete",
        token = private$token, cookies = private$cookies,
        user = private$user,
        pwd = keyring::key_get(private$keyring_service, username = private$user),
        content = gnRequest$encode(),
        contentType = "text/xml",
        verbose = self$verbose.debug
      )
      if(status_code(req) == 200){
        self$INFO("Successfully deleted metadata!")
        response <- GNUtils$parseResponseXML(req)
        out <- as.integer(xpathApply(response, "//id", xmlValue)[[1]])
      }else{
        self$ERROR(sprintf("Error while deleting metadata - %s", message_for_status(status_code(req))))
        self$ERROR(content(req))
      }
      return(out)
    },
    
    #deleteMetadataAll
    #---------------------------------------------------------------------------
    deleteMetadataAll = function(){
      self$INFO("Deleting all owned metadata...")
      
      if(self$version$lowerThan("2.10.x")){
        stop("Method unsupported for GN < 2.10.X")
      }
      
      #select all
      gnSelectRequest <- GNRESTRequest$new()
      gnSelectRequest$setChild("selected", "add-all")
      selectReq <- GNUtils$POST(
        url = self$getUrl(),
        path = "/xml.metadata.select",
        token = private$token, cookies = private$cookies,
        user = private$user,
        pwd = keyring::key_get(private$keyring_service, username = private$user),
        content = gnSelectRequest$encode(),
        contentType = "text/xml",
        verbose = self$verbose.debug
      )
      #delete all
      gnDeleteRequest <- GNRESTRequest$new()
      deleteReq <- GNUtils$POST(
        url = self$getUrl(),
        path = "/xml.metadata.batch.delete",
        token = private$token, cookies = private$cookies,
        user = private$user,
        pwd = keyring::key_get(private$keyring_service, username = private$user),
        content = gnDeleteRequest$encode(),
        contentType = "text/xml",
        verbose = self$verbose.debug
      )
      response <- GNUtils$parseResponseXML(deleteReq)
      return(response)
    }
  )
                     
)
