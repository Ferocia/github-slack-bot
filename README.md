# Github Slack Bot

This Slack bot takes Github webhooks and pings relevant people on Slack on Github events so you don't have to check your emails all the time.

## Features

* Notifies people via a Slack channel so people can configure their notification options accordingly
* Supports the following Github events:
  * Commit status
  * Issue open
  * Issue comment
  * PR comment
  * Commit comment

## Usage

Deploy it somewhere. Heroku makes it easy.

[![Deploy](https://www.herokucdn.com/deploy/button.svg)](https://heroku.com/deploy?template=https://github.com/chendo/github-slack-bot)

Add a Github webhook and point it to where you've deployed it, factoring in `WEBHOOK_PATH` (see below), e.g. `https://my-github-slack-bot.herokuapp.com/secret-webhook-url`. You can choose to send all events or select the events you care about.

## Options

All options are set by environment variables.

Required:

* `SLACK_WEBHOOK_URL` - A Slack incoming webhook URL
* `SLACK_CHANNEL` - The Slack channel you want events to be posted to.

Optional:

* `WEBHOOK_PATH` - Defaults to `/`. You'll want to change this to something hard to guess, otherwise technically anyone can send you Github events.
* `SLACK_USERNAME_FOR_[GITHUB_USERNAME]` - By default, the bot will mention the Github username on Slack. If your Slack username differs from your Github username, then you'll want to set this. For example, if your Github username is `@l33thax` but your company mandates boring names like `@joe.bloggs`, then you would set `SLACK_USERNAME_FOR_L33THAX=joe.bloggs`.
* `STATUS_EVENTS` - Defaults to `success,failure,error`. A comma-separated list of commit status types. Available are `pending`, `success`, `failure`, `error`. You may want to set this if you only want to be notified of failures/errors.
* `STATUS_CONTEXTS` - Defaults to ``. A regular expression of commit status contexts to notify on. For example, `^buildkite\/` to only notify on [Buildkite](https://buildkite.com/) commit status events.
* `IGNORED_EVENTS` - Defaults to ``. A comma-separated list of Github event keys. See `Webhook event name` on an event at https://developer.github.com/v3/activity/events/types/
* `HIDE_DIFFS` - When set, notifications won't render diffs.

## License

MIT.
