' ********** Copyright 2019 Roku Corp.  All Rights Reserved. **********

sub GetContent()

    appInfo = CreateObject("roAppInfo")
    feedURL = appInfo.GetValue("FEED_URL")

    MAXSIZE = 500 * 1024

    print feedURL

    url = CreateObject("roUrlTransfer")
    url.SetUrl(feedURL)
    url.EnablePeerVerification(false)
    url.SetCertificatesFile("pkg:/certs/ca-bundle.crt")
    url.AddHeader("X-Roku-Reserved-Dev-Id", "")
    url.InitClientCertificates()
    feed = url.GetToString()
    
    #if false
    'this is for a sample, usually feed is retrieved from url using roUrlTransfer
    'feed = ReadAsciiFile("pkg:/feed/feed.json")
    'feed = ReadAsciiFile("pkg:/feed/mRSS_Feed.xml")
    'feed = ReadAsciiFile("pkg:/feed/large_feed.json")
    'Sleep(2000) ' to emulate API call
    #endif

    if( feed.Len() < MAXSIZE AND feed.len() > 0 )
        if( feed.StartsWith("<?xml") or feed.StartsWith("<rss"))
            feedType = "XML"
            parsed = parseMRSS(feed)
        else
            'assuming JSON
            feedType = "JSON"
            parsed = parseRokuFeedSpec(feed)
            
        endif 
    else
        if( feed.Len() > MAXSIZE )
            'any feed over 500Kb is too large to parse locally
            print "FEED is too large: ", feed.Len()
            rootChildren = {
                children: []
                }
                children = []
            itemNode = CreateObject("roSGNode", "ContentNode")
                Utils_ForceSetFields(itemNode, {
                    hdPosterUrl: "pkg:/images/feed_too_large.jpg"
                    Description: "Feed is too large"
                    id: "0"
                    Categories: "Feed is too large"
                    title: "Feed is too large"
                    url: ""
                })
            children.Push(itemNode)
            rowAA = {
                title: "Feed is too large"
                children: children
                }
            rootChildren.children.Push(rowAA)
            m.top.content.Update(rootChildren)
        else
            print "Cannot obtain Feed: ", feed.Len()
            rootChildren = {
                children: []
                }
                children = []
            itemNode = CreateObject("roSGNode", "ContentNode")
                Utils_ForceSetFields(itemNode, {
                    hdPosterUrl: ""
                    Description: "Cannot obtain Feed"
                    id: "0"
                    Categories: "Cannot obtain Feed"
                    title: "Cannot obtain Feed"
                    url: ""
                })
            children.Push(itemNode)
            rowAA = {
                title: "Cannot obtain Feed"
                children: children
                }
            rootChildren.children.Push(rowAA)
            m.top.content.Update(rootChildren) 
        endif
    endif   
end sub

'
' Parse Roku feed spec, majority of Direct Publisher 
' channels will fall into this category 
'
function parseRokuFeedSpec(xmlString as string) as Object
        json = ParseJson(xmlString)
        if json <> invalid ' and json.rows <> invalid and json.rows.Count() > 0
            rootChildren = {
            children: []
            }
            channelsByTag = {
                "now-live": { name: "Now Live", channels: [] },
                "music": { name: "Music", channels: [] },
                "tech": { name: "Tech", channels: [] },
                "chatting": { name: "Chatting", channels: [] },
                "video-games": { name: "Video Games", channels: [] },
                "now-offline": { name: "Offline", channels: [] }
            }
 
            allChannels = {
                name: "All Feeds"
                channels: []
            }

            tagOrder = ["now-live", "music", "tech", "chatting", "video-games", "now-offline"]
            for each item in json
                value = json[item]
                if item = "movies" or item = "series" or item = "shortFormVideos" or item = "tvSpecials" or item = "liveFeeds"
                    for each arrayItem in value
                        if item = "movies" or item = "shortFormVideos" or item = "tvSpecials" or item = "liveFeeds"
                        end if
                        for each tag in arrayItem["tags"]
                            if channelsByTag.DoesExist(tag)
                                itemNode = CreateObject("roSGNode", "ContentNode")
                                Utils_ForceSetFields(itemNode, {
                                    hdPosterUrl: arrayItem.thumbnail
                                    Description: arrayItem.shortDescription
                                    id: arrayItem.id
                                    Categories: ConvertToStringAndJoin(arrayItem["tags"], ", ")
                                    title: arrayItem.title
                                })
                                itemNode.Url = arrayItem.content.videos[0].url
                                channelsByTag[tag].channels.Push(itemNode)
                            end if
                        end for

                        ' Seems you need a unique ContentNode per place in the grid
                        ' so this one is for the "all feeds" one
                        itemNode = CreateObject("roSGNode", "ContentNode")
                        Utils_ForceSetFields(itemNode, {
                            hdPosterUrl: arrayItem.thumbnail
                            Description: arrayItem.shortDescription
                            id: arrayItem.id
                            Categories: ConvertToStringAndJoin(arrayItem["tags"], ", ")
                            title: arrayItem.title
                        })
                        itemNode.Url = arrayItem.content.videos[0].url
                        allChannels.channels.Push(itemNode)
                    end for
                end if
            end for

            ' Render out the rows here
            for each tag in tagOrder
                row = {
                    title: channelsByTag[tag].name
                    children: channelsByTag[tag].channels
                }
                rootChildren.children.Push(row)
            end for
            allChannelsRow = {
                title: allChannels.name
                children: allChannels.channels
            }
            rootChildren.children.Push(allChannelsRow)
            m.top.content.Update(rootChildren)
        end if
end function

function GetEpisodeNodeFromJSON(episode)
    result = CreateObject("roSGNode", "ContentNode")

    result.SetFields({
        title: episode.title
        url: episode.content.videos[0].url
        hdPosterUrl: episode.thumbnail
        description: episode.shortDescription
    })

    return result
end function

'
' MRSS parser
'
function parseMRSS(xmlString as string) as Object
    xmlParser = createObject("roXMLElement")
    if xmlParser.parse(xmlString) then
        if xmlParser.getName() = "rss" then
            return parseRSS(xmlParser)
        elseif xmlParser.getName() = "feed" then
            return parseAtom(xmlParser)
        else
            return invalidMRSS("Invalid MRSS format")
        end if
    else
        return invalidMRSS("Failed to parse MRSS")
    end if
end function

'
' All mRSS feeds present in the top 50 channels (which there are very few)
' seem to fall into this structure 
'
function parseRSS(xmlParser as Object) as Object
    responseXML = xmlParser.GetChildElements()
    responseArray = xmlParser.GetChildElements()

    rootChildren = {
        children: []
        }
    children = [] 

    for each xmlItem in responseArray 
        if xmlItem.getName() = "channel"
            channelAA = xmlItem.GetChildElements()
            for each channel in channelAA
                if channel.getName() = "item" 
                    itemAA = channel.GetChildElements() '
                    if itemAA <> invalid 
                        items = {} 
                        itemNode = CreateObject("roSGNode", "ContentNode")
                                Utils_ForceSetFields(itemNode, {
                                    Description: ""
                                    id: ""
                                    Categories: ""
                                    title: ""
                                })
                        for each item in itemAA 
                            items[item.getName()] = item.getText()
                            if item.getName() = "title"
                                itemNode.title = item.getText()
                            endif

                            if item.getName() = "description"
                                itemNode.Description = item.getText()
                            endif

                            if item.getName() = "media:content" 'Checks to find <media:content> header
                                itemNode.url = item.getAttributes().url
                                itemNode.streamFormat = "" 'allow media player to try to autodetect 

                                mediaContent = item.GetChildElements()
                                for each mediaContentItem in mediaContent 
                                    if mediaContentItem.getName() = "media:thumbnail"
                                        itemNode.HDPosterUrl = mediaContentItem.getattributes().url 'Assigns images to item AA
                                        itemNode.hdBackgroundImageUrl = mediaContentItem.getattributes().url
                                    end if
                                end for
                            end if
                        end for
                        children.push(itemNode)
                    end if
                end if
            end for
            rowAA = {
                title: items
                children: children
            }
            rootChildren.children.Push(rowAA)
        end if
    end for
    m.top.content.Update(rootChildren)
    return rootChildren 
end function

'
' I haven't found any feeds that fall into this scenario
' we probably don't need this? 
'
function parseAtom(xmlParser as Object) as Object
    mrss = {}
    mrss["title"] = xmlParser.GetNamedElements("title").getText()
    mrss["items"] = []
    
    for each entry in xmlParser.GetNamedElements("entry")
        mrssItem = {}
        mrssItem["title"] = entry.GetNamedElements("title").getText()
        mrssItem["description"] = entry.GetNamedElements("summary").getText()
        mrssItem["pubDate"] = entry.GetNamedElements("published").getText()
        mrssItem["media"] = []
        
        for each media in entry.GetNamedElements("media:content")
            mrssMedia = {}
            mrssMedia["url"] = media.GetNamedElements("url")
            mrssMedia["type"] = media.GetNamedElements("type")
            mrssMedia["width"] = media.GetNamedElements("width")
            mrssMedia["height"] = media.GetNamedElements("height")
            mrss["media"].Append(mrssMedia)
        end for
        
        mrss["items"].Append(mrssItem)
    end for
    
    return mrss
end function

function invalidMRSS(message as string) as Object
    return {
        "error": true,
        "message": message
    }
end function

function ConvertToStringAndJoin(dataArray as Object, divider = " | " as String) as String
    result = ""
    if Type(dataArray) = "roArray" and dataArray.Count() > 0
        for each item in dataArray
            if item <> invalid
                strFormat = invalid
                if GetInterface(item, "ifToStr") <> invalid
                    strFormat = item.Tostr()
                else if GetInterface(item, "ifArrayJoin") <> invalid
                    strFormat = item.Join(" | ")
                end if
                if strFormat <> invalid then
                    if strFormat.Len() > 0
                        if result.Len() > 0 then result += divider
                        result += strFormat
                    end if
                end if
            end if
        end for
    end if
    return result
end function

