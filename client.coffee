Loglist = require 'loglist'
Db = require 'db'
Dom = require 'dom'
Event = require 'event'
Social = require 'social'
Modal = require 'modal'
Time = require 'time'
Form = require 'form'
Obs = require 'obs'
Plugin = require 'plugin'
Colors = Plugin.colors()
Page = require 'page'
Server = require 'server'
Ui = require 'ui'
{tr} = require 'i18n'
Photo = require 'photo'
Photoview = require 'photoview'

###
# Main page rendering function
###
exports.render = !->
    # Decide which page to render based on current state
    pg = Page.state.get()

    # TODO fix page navigation, I seem to have misunderstood the purpose of Page.state and Page.nav
    if pg.viewPicture
        renderPhotoView(pg.viewPicture, {del: pg.delpic})
    else if typeof(pg.offerBids) != 'undefined'
        renderOfferBids(pg.offerBids)
    else if typeof(pg.offer) != 'undefined'
        renderViewOffer(pg.offer)
    else if pg.page
        switch pg.page
            when "editOffer" then renderEditOffer(pg.offerID)
            else renderOffers()
    else
        renderOffers()


###
# Renders the list of bids for the offer with the given id
#
# @param id The ID of the offer of which to render the bids
###
renderOfferBids = (id) !->
    offer = Db.shared.get('offers', id)
    Page.setTitle "Bids on #{offer.title}"
    highestBid = offer.highestBid

    # Allow bidding for all users except 'owner' of offer
    if Plugin.userId() != offer.user
        Dom.section !->
            # If reserved, do not allow placing bids
            if offer.reserved
                Dom.div !->
                    Dom.style fontWeight: 'bold', textAlign: 'center', background: '#FDFD96'
                    Dom.text "This offer is currently reserved"
            else
                Dom.div !->
                    Dom.style textAlign: 'center'
                    Form.input
                        name: 'bid'
                        text: 'Bid'
                        value: parseInt(highestBid)+1
                    Dom.last().style width: '60px', margin: '0px 10px', textAlign: 'center', display: 'inline-block', padding: '5px 4px'
                    Ui.button "Place bid", !->
                        bid = Form.values().bid
                        if parseInt(bid) <= highestBid || bid == ''
                            Modal.show "Place a bid higher than #{highestBid}!"
                        else
                            Server.sync 'placeBid', id, bid

    # Render actual bids, if any
    if highestBid > 0
        Ui.list !->
            Db.shared.iterate 'offers', id, 'bids', (bid) !->
                Ui.item !->
                    Dom.style display: 'block'
                    Dom.div !->
                        Dom.style display: 'inline-block', lineHeight: '40px', verticalAlign: 'middle'
                        Dom.div !->
                            Dom.style display: 'inline-block', lineHeight: '40px', verticalAlign: 'middle'
                            Ui.avatar Plugin.userAvatar(bid.get('user')),
                                onTap: !->
                                    Plugin.userInfo(bid.get('user'))
                        Dom.span !->
                            Dom.style verticalAlign: 'middle', lineHeight: '40px', marginLeft: '6px'
                            Dom.text Plugin.userName(bid.get('user'))

                    # Allow owner of bid and owner of offer to remove bid
                    if bid.get('user') == Plugin.userId() || Plugin.userId() == offer.user
                        Dom.div !->
                            Dom.style
                                display: 'inline-block'
                                verticalAlign: 'middle'
                                lineHeight: '40px'
                                position: 'relative'
                                top: '7px'
                                float: 'right'
                                marginLeft: '10px'
                                background:  "url(#{Plugin.resourceUri('icon-trash-48.png')}) 50% 50% no-repeat"
                                backgroundSize: '24px'
                                height: '24px'
                                width: '24px'
                            Dom.onTap !->
                                if Plugin.userId() == offer.user
                                    Modal.confirm "Do you want to delete this bid?", !->
                                        Server.sync 'deleteBid', id, bid.get('amount')
                                else
                                    Modal.confirm "Do you want to delete your bid?", !->
                                        Server.sync 'deleteBid', id, bid.get('amount')
                    Dom.span !->
                        Dom.style display: 'inline-block', float: 'right', verticalAlign: 'middle', lineHeight: '40px'
                        Dom.text "\u20AC " + bid.get('amount')
            , (bid) -> -bid.get('amount')
    else
        Dom.section !->
            Dom.style textAlign: 'center', fontWeight: 'bold'
            Dom.text "No bids yet"


###
# Renders the photo with the given key/id and options
#
# @param id The key of the photo to render
# @param opts Object with options:
#   del: Whether there should be the option to delete this photo
#   title: Title of view
###
renderPhotoView = (id, opts) !->
    Page.setTitle(if opts.title then opts.title else "Picture")
    if opts.del == true
        Page.setActions
            icon: "trash"
            label: "Delete"
            action: !->
                Modal.confirm null, tr("Remove photo?"), !->
                    Server.send 'removeSubmitPicture', id
                    Page.back()

    Dom.div !->
        Dom.style
            position: 'relative'
            height: Dom.viewport.get('width') + 'px'
            width: Dom.viewport.get('width') + 'px'
            background: Photo.css id, 800
            backgroundPosition: '50% 50%'
            backgroundSize: 'cover'


###
# Renders all current offers
###
renderOffers = ->
    Page.setTitle "Current Offers"
    Page.setFooter
        label: "New Offer"
        action: !-> Page.nav page: "editOffer", offerID: "new"

    Dom.div !->
        Dom.style textAlign: 'center'
        Dom.h3 "Current Offers"

    if parseInt(Db.shared.get 'maxOfferID') == -1 || Db.shared.get 'offers' == []
        Dom.section !->
            Dom.div !->
                Dom.style textAlign: "center"
                Dom.h4 "No offers yet!"
    else
        Ui.list !->
            Db.shared.iterate 'offers', (offer) !->
                Ui.item !->
                    # Combat some server-side bug that causes a weird object to be added to the database sometimes
                    if typeof(offer.get('title')) != 'undefined'
                        renderOfferItem(offer)
            , (offer) -> 1-parseInt(offer.get('date'))


###
# Renders the contents of the list item for the given offer
#
# @param o The offer to render in the list of offers
###
renderOfferItem = (o) !->
    Dom.div !->
        offerID = o.get('id')
        if typeof offerID == 'undefined'
            offerID = -1
        Dom.onTap !->
            if o.get('user') != Plugin.userId()
                Server.sync 'viewOffer', parseInt(offerID)
            Page.nav offer: parseInt(offerID)
        Dom.style width: '100%'

        pic = o.get('images')[0]
        if typeof(pic) != 'undefined'
            Dom.img !->
                Dom.style
                    maxWidth: '60px'
                    maxHeight: '60px'
                    margin: '2px 8px 4px 2px'
                    verticalAlign: 'middle'
                Dom.prop('src', Photo.url pic)
        Dom.span !->
            Dom.style verticalAlign: 'middle', lineHeight: '30px'
            if typeof(pic) != 'undefined'
                Dom.style lineHeight: '60px'
            Dom.text o.get('title')
        Dom.span !->
            if o.get('reserved') == true
                Dom.style float: 'right', verticalAlign: 'middle', color: 'orange', fontWeight: 'bold', lineHeight: '30px'
                if typeof(pic) != 'undefined'
                    Dom.style lineHeight: '60px'
                Dom.text 'Reserved'
            else
                Dom.style float: 'right', verticalAlign: 'middle', lineHeight: '30px'
                if typeof(pic) != 'undefined'
                    Dom.style lineHeight: '60px'
                Dom.text "\u20AC " + o.get('price')

###
# Renders view to view a posted offer
#
# @param id The ID of the offer to render
###
renderViewOffer = (id) !->
    # Check for non-existing offers
    offer = Db.shared.get 'offers', id
    Page.setTitle "#{offer.title}"
    if id == -1 || typeof('offer') == 'undefined'
        log id
        Dom.section !->
            Dom.style textAlign: 'center'
            Dom.h3 "Error: Invalid offer"
            Dom.text "This offer does not exist. Maybe it has been deleted?"
        return

    # Allow offer 'owner' and Admins to delete offers
    if offer.user == Plugin.userId() || Plugin.userIsAdmin()
        Page.setActions
            icon: "edit"
            label: "Edit"
            action: !->
                Page.nav page: "editOffer", offerID: id

    # Offer details
    Dom.section !->
        Dom.div !->
            Dom.style borderBottom: '1px solid #dedede', paddingBottom: '5px', marginBottom: '10px'
            Dom.div !->
                Dom.style display: 'inline-block', lineHeight: '40px', verticalAlign: 'middle'
                Dom.div !->
                    Dom.style display: 'inline-block', lineHeight: '40px', verticalAlign: 'middle'
                    Ui.avatar Plugin.userAvatar(),
                        onTap: !->
                            Plugin.userInfo(Plugin.userId())
                Dom.span !->
                    Dom.style verticalAlign: 'middle', lineHeight: '40px', marginLeft: '6px'
                    Dom.text Plugin.userName()
            Dom.span !->
                Dom.style display: 'inline-block', float: 'right', verticalAlign: 'middle', lineHeight: '40px'
                if offer.reserved
                    Dom.style color: 'orange', fontWeight: 'bold'
                    Dom.text 'Reserved'
                else
                    Dom.b "Price:  \u20AC "
                    Dom.text offer.price
        Dom.div !->
            Dom.style paddingBottom: '5px'
            Dom.h3 offer.title
            Dom.pre offer.description
            Dom.last().style fontFamily: "Roboto", marginBottom: '5px', marginTop: '7px'
        if offer.images.length > 0
            Dom.div !->
                Dom.style overflowX: 'auto', minHeight: '120px', maxHeight: '120px'
                for key in offer.images
                    Dom.img !->
                        Dom.style
                            width: '120px'
                            height: '120px'
                            verticalAlign: 'middle'
                            margin: '0px 5px'
                        Dom.prop('src', Photo.url key)
                        Dom.onTap !->
                            Page.nav viewPicture: key

        Dom.div !->
            Dom.style textAlign: 'right', fontStyle: 'italic', fontSize: '14px'
            Dom.text "Views: #{offer.views||0}"


    # Bids information
    Dom.section !->
        Dom.div !->
            Dom.style marginBottom: '0px', paddingBottom: '0px'
            Dom.onTap !->
                Page.nav offerBids: offer.id
            if Plugin.userId() == offer.user
                Dom.div !->
                    Dom.style verticalAlign: 'middle', lineHeight: '100%', display: 'inline-block', marginRight: '5px'
                    if Db.shared.get 'offers', offer.id, 'reserved'
                        Ui.button "Unreserve", !->
                            Modal.confirm "Do you want to remove the reservation on this offer?", !->
                                Server.sync "reserveOffer", id, false
                    else
                        Ui.button "Reserve", !->
                            Modal.confirm "Do you want to reserve this offer for a bidder?", !->
                                Server.sync "reserveOffer", id, true
                Dom.div !->
                    Dom.style verticalAlign: 'middle', lineHeight: '100%', display: 'inline-block'
                    Ui.button "View bids"
            else
                Dom.div !->
                    Dom.style verticalAlign: 'middle', lineHeight: '100%', display: 'inline-block'
                    Ui.button "Place bid"

            if offer.highestBid == 0
                Dom.div !->
                    Dom.style fontWeight: 'bold', display: 'inline-block', verticalAlign: 'middle', lineHeight: '35px', float: 'right',
                    Dom.text "No bids yet"
            else
                Dom.div !->
                    Dom.style fontWeight: 'bold', display: 'inline-block', verticalAlign: 'middle', lineHeight: '35px', float: 'right',
                    Dom.text "Highest bid: #{offer.highestBid} "
                    if offer.hasOwnProperty('highestBidBy') && offer.highestBidBy != -1
                        Ui.avatar Plugin.userAvatar(offer.highestBidBy),
                            onTap: !->
                                Plugin.userInfo(offer.highestBidBy)
                        Dom.last().style verticalAlign: 'middle', marginLeft: '5px'
    Social.renderComments offer.id


###
# Renders page for edit offers or creating new ones
###
renderEditOffer = (offerID) !->
    # Page setup
    offer = null
    rules = Db.shared.get 'rules'

    if offerID != "new"
        offer = Db.shared.get 'offers', offerID
        Server.sync 'startEditingOffer', offerID
        Page.setActions
            icon: "trash"
            label: "Delete"
            action: !->
                Modal.confirm null, "Do you want to permanently delete this offer?", !->
                    Server.sync 'deleteOffer', offerID, ->
                    Page.back()

    Page.setTitle if offerID == "new" then "New offer" else "Edit offer"
    Dom.div !->
        Dom.style textAlign: "center"
        Dom.h3 if offer then "Edit Offer" else "New Offer"

    if rules? && rules != ''
        Dom.section !->
            Dom.style textAlign: 'center', background: '#FBFFC2'
            Dom.b "Marketplace rules: "
            Dom.text rules

    ### Render input form ###
    Dom.section !->
        # Title
        Dom.div !->
            Dom.div !->
                Dom.style display: "inline-block", width: (Dom.viewport.get('width')-120) + 'px'
                Form.input
                    name: "title"
                    text: if offer then offer.title else "Title"
                    title: "Title"
                    value: if offer then offer.title else ""
            Dom.div !->
                Dom.style display: "inline-block", width: "62px", float: "right"
                Form.input
                    name: "price"
                    text: "\u20AC"
                    title: "Price"
                    value: if offer then offer.price else ""

        # Photos
        Dom.div !->
            renderPhotoPicker()
            pics = Db.shared.get 'submitPictures', Plugin.userId(), "pictures"
            for pic in pics
                renderPhoto(pic)

        # Description
        Form.text
            name: "description"
            text: if offer then offer.description else "Descrption"
            title: "Description"
            value: if offer then offer.description else ""

        # If rules are set, require users to agree with them
        if rules? && rules != ''
            Dom.div !->
                Dom.span !->
                    Dom.style verticalAlign: 'middle', lineHeight: '30px'
                    Dom.text "I will adhere to the marketplace rules "
                Form.check
                    name: 'agreedToRules'
                    value: false
                    title: "I agree to the marketplace rules"
                Dom.last().style verticalAlign: 'middle', display: 'inline-block', float: 'right', lineHeight: '30px'

        Form.setPageSubmit (values) !->
            # Validate input and if successful submit
            if !values.title
                Modal.show("Please enter a title")
                return
            if !values.description
                Modal.show("Please enter a description")
                return
            if rules? && rules != '' && !values.agreedToRules
                Modal.show("Please confirm you will adhere to the marketplace rules")
                return
            values.title = Form.smileyToEmoji values.title
            values.description = Form.smileyToEmoji values.description
            values.price = parseInt(values.price)
            if offer
                Server.sync 'editOffer', offerID, values, !->
                Page.back()
            else
                Server.sync 'newOffer', values, !->
                Page.back()
        , offerID != 'new'

###
# Renders an image functioning as a photo picker to upload photos
###
renderPhotoPicker = !->
    width = Dom.viewport.get('width')
    cnt = (0|(width / 100)) || 1
    boxSize = 0|(width-((cnt+1)*4))/cnt

    Dom.div !->
        Dom.cls 'add'
        Dom.style
            display: 'inline-block'
            position: 'relative'
            verticalAlign: 'top'
            margin: '2px'
            background:  "url(#{Plugin.resourceUri('addphoto.png')}) 50% 50% no-repeat"
            backgroundSize: '32px'
            border: 'dashed 2px #aaa'
            height: (boxSize-4) + 'px'
            width: (boxSize-4) + 'px'
        Dom.onTap !->
            Photo.pick()


###
# Renders a photo with the given key in a small frame
#
# @param key The secret key of the photo to render
###
renderPhoto = (key) !->
    width = Dom.viewport.get('width')
    cnt = (0|(width / 100)) || 1
    boxSize = 0|(width-((cnt+1)*4))/cnt

    Dom.div !->
        Dom.style
            display: 'inline-block'
            margin: '2px'
            width: boxSize + 'px'
        Dom.div !->
            Dom.style
                display: 'inline-block'
                marginLeft: "5px"
                marginRight: "5px"
                position: 'relative'
                height: boxSize + 'px'
                width: boxSize + 'px'
                background: "url(#{Photo.url key}) 50% 50% no-repeat"
                backgroundSize: 'cover'
            Dom.cls 'photo'
            Dom.onTap !->
                Page.nav viewPicture: key, delpic: true

###
# Plugin settings page
###
exports.renderSettings = !->
    Dom.div !->
        Dom.text "You can enter marketplace rules which are visible to users when adding offers. If not left empty, users will be required to indicate they agree with the marketplace rules before they can post an offer."

    Form.text
        name: 'rules'
        text: "Marketplace rules"
        value: Db.shared.get('rules') if Db.shared