Db = require 'db'
Plugin = require 'plugin'
Event = require 'event'
Timer = require 'timer'
Photo = require 'photo'
{tr} = require 'i18n'

# Setup database of offers and submitted pictures
exports.onInstall = ->
    log 'Installing database...'
    Db.shared.set 'offers', []
    Db.shared.set 'maxOfferID', -1
    Db.shared.set 'submitPictures', {}

###
# Add new offer to database
###
exports.client_newOffer = (o) !->
    nextID = Db.shared.modify 'maxOfferID', (v) -> v+1
    currentTime = Math.round(Date.now()/1000)

    # Create new offer
    offer =
        id:             nextID
        title:          (o.title||"Title")
        description:    (o.description||"Description")
        price:          (o.price||0)
        user:           Plugin.userId()
        date:           currentTime
        reserved:       false
        bids:           []
        highestBid:     0
        highestBidBy:   -1
        numBids:        0
        views:          0

    # Add all submitted images to it and remove them from submitted array
    offer.images = []
    Db.shared.iterate 'submitPictures', Plugin.userId(), "pictures", (pic) !->
        offer.images.push(pic.get())
    Db.shared.set 'submitPictures', Plugin.userId(), "pictures", []
    Db.shared.set 'submitPictures', Plugin.userId(), "numPictures", 0

    Db.shared.set "offers", nextID, offer
    log "#{Plugin.userName(offer.user)} added a new offer with ID #{nextID}"

    Event.create
        unit: 'offer'
        text: "New offer: #{offer.title}"
        exclude: [Plugin.userId()]

###
# Called when a user other than the offer 'owner' clicks on an offer
# in the list of offers. This is regarded as one view.
#
# @param offerID The ID of the offer of which to increment the view count
###
exports.client_viewOffer = (offerID) !->
    if Db.shared.get 'offers', offerID, 'user' != Plugin.userId()
        Db.shared.modify 'offers', offerID, 'views', (v) -> (v||0)+1


###
# Called when a photo is uploaded by the cliet Photo api
###
exports.onPhoto = (info) !->
    if typeof(Db.shared.get 'submitPictures', Plugin.userId(), "numPictures") == "undefined"
        Db.shared.set "submitPictures", Plugin.userId(), "numPictures", 0
        Db.shared.set "submitPictures", Plugin.userId(), "pictures", 0, info.key
    else
        nextID = Db.shared.modify "submitPictures", Plugin.userId(), "numPictures", (v) -> v+1
        Db.shared.set "submitPictures", Plugin.userId(), "pictures", nextID, info.key


###
# Removes the picture with the given key
###
exports.client_removeSubmitPicture = (key) !->
    Photo.remove key
    pics = Db.shared.get "submitPictures", Plugin.userId(), "pictures"
    for k,v of pics
        if v == key
            Db.shared.remove "submitPictures", Plugin.userId(), "pictures", k
            break

###
# Places a bid for the given offer
###
exports.client_placeBid = (offerID, bid) !->
    offer = Db.shared.get 'offers', offerID
    if typeof(offer) != 'undefined' && offer.user != Plugin.userId()
        if parseInt(offer.highestBid) < parseInt(bid)
            newBid =
                amount: parseInt(bid)
                user:   Plugin.userId()
            newID = Db.shared.modify 'offers', offerID, 'numBids', (v) -> v+1
            Db.shared.set 'offers', offerID, 'bids', (newID-1), newBid
            Db.shared.set 'offers', offerID, 'highestBid', bid
            Db.shared.set 'offers', offerID, 'highestBidBy', Plugin.userId()

            # Send events to all other bidders
            recipients = []
            Db.shared.iterate 'offers', offerID, 'bids', (b) !->
                bidder = b.get('user')
                if parseInt(b.get('amount')) < parseInt(bid)
                    if bidder not in recipients and bidder != Plugin.userId()
                        recipients.push(bidder)
            Event.create
                unit: 'overbidden'
                text: "#{Plugin.userName()} bid higher on #{offer.title}"
                include: recipients

            # Send event to offer owner
            Event.create
                unit: 'bid'
                text: "New bid of #{bid} for #{offer.title}"
                include: [offer.user]

###
# Deletes the bid for the given offer and of the given amount,
# placed by the currently logged in user
###
exports.client_deleteBid = (offerID, amount) !->
    offer = Db.shared.get 'offers', offerID
    bids = offer.bids
    highestBid = 0
    for k,v of bids
        if v.user == Plugin.userId() && parseInt(v.amount) == parseInt(amount)
            Db.shared.remove 'offers', offerID, 'bids', k
            Event.create
                unit: 'revokeOffer'
                text: "Offer of #{amount} revoked for #{offer.title}"
                include: [offer.user]
        else
            if parseInt(v.amount) > parseInt(highestBid)
                highestBid = parseInt(v.amount)
    Db.shared.set 'offers', offerID, 'highestBid', highestBid


###
# Reserves or 'unreserves' the given offer
###
exports.client_reserveOffer = (offer, reserve) !->
    o = Db.shared.get 'offers', offer
    if Plugin.userId() == o.user
        Db.shared.set 'offers', offer, 'reserved', reserve

        # Send event to all bidders
        if reserve
            recipients = []
            Db.shared.iterate 'offers', offer, 'bids', (b) !->
                bidder = b.get('user')
                if bidder not in recipients and bidder != Plugin.userId()
                    recipients.push(bidder)
            Event.create
                unit: 'reserved'
                text: "#{o.title} has been reserved"
                include: recipients

###
# Deletes the given offer
###
exports.client_deleteOffer = (offer) !->
    o = Db.shared.get 'offers', offer
    if Plugin.userId() == o.user
        Db.shared.remove 'offers', offer
    else if Plugin.userIsAdmin()
        Event.create
            unit: 'removedByAdmin'
            text: "An admin removed your offer #{o.title}"
            include: o.user
        Db.shared.remove 'offers', offer