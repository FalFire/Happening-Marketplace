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
        numBids:        0

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
        include: [Plugin.userId()]


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
exports.client_deleteBid = (offer, amount) !->
    bids = Db.shared.get 'offers', offer, 'bids'
    offer = Db.shared.get 'offers', offer
    highestBid = 0
    for k,v of bids
        if v.user == Plugin.userId() && v.amount == amount
            Db.shared.remove 'offers', offer, 'bids', k
            Event.create
                unit: 'revokeOffer'
                text: "Offer of #{amount} revoked for #{offer.title}"
                include: [offer.user]
        else
            if v.amount > highestBid
                highestBid = v.amount
    Db.shared.set 'offers', offer, 'highestBid', highestBid


###
# Reserves or 'unreserves' the given offer
###
exports.client_reserveOffer = (offer, reserve) !->
    o = Db.shared.get 'offers', offer
    if Plugin.userId() == o.user
        Db.shared.set 'offers', offer, 'reserved', reserve

###
# Deletes the given offer
###
exports.client_deleteOffer = (offer) !->
    o = Db.shared.get 'offers', offer
    if Plugin.userId() == o.user || Plugin.userIsAdmin()
        Db.shared.remove 'offers', offer