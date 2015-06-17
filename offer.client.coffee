Dom = require 'dom'
Db = require 'db'
Form = require 'form'
Obs = require 'obs'
Page = require 'page'
Plugin = require 'plugin'
Colors = Plugin.colors()
{tr} = require 'i18n'

maxOfferID = Db.shared.get("maxOfferID")

class Offer
    # Instance variables
    contents: ''

    # Constructor
    constructor: (contents) ->
        @contents = contents
        @id = maxOfferID+1
        maxOfferID.modify (v) -> v+1

    getContents: -> @contents

exports.Offer = Offer