require 'bundler'
Bundler.require
require 'yaml'

class GithubSlackBot < Sinatra::Base
  configure :production, :development do
    enable :logging
    set :server, :puma
    set :port, ENV.fetch('PORT', 9292).to_i
  end

  SLACK_WEBHOOK_URL = ENV.fetch('SLACK_WEBHOOK_URL')
  SLACK_CHANNEL = ENV.fetch('SLACK_CHANNEL')

  post ENV.fetch('WEBHOOK_PATH', '/') do
    request.body.rewind
    data = JSON.parse(request.body.read)

    event = request.env['HTTP_X_GITHUB_EVENT']
    EventHandler.new(event, data).process

    'OK'
  end

  protected

  class EventHandler
    attr_reader :data, :event
    def initialize(event, data)
      @event = event
      @data = Hashie::Mash.new(data)
    end

    def process
      return if ENV.fetch('IGNORED_EVENTS', '').split(/\s*,\s*/).include?(event)
      case event
      when 'status'
        process_status
      when 'issues'
        process_issue
      when 'issue_comment', 'pull_request_review_comment'
        process_issue_comment
      when 'commit_comment'
        process_commit_comment
      end
    rescue StandardError => ex
      send_slack_message({
        text: "Error: #{ex}\n#{ex.backtrace[0...5].join("\n")}"
      })
    end

    protected

    def process_status
      state = data.state
      context = data.context
      description = data.description
      target_url = data.target_url

      return unless ENV.fetch('STATUS_EVENTS', 'success,failure,error').split(/,/).include?(state)
      return unless context =~ Regexp.new(ENV.fetch('STATUS_CONTEXTS', ''))

      notify(["@#{commit_author}"], attachments: [
        {
          fallback: "*Build status*\n#{repo} - #{branches.join(', ')}\n`#{context}`: #{state} - #{description}\nSee More: #{target_url}",
          title: "#{repo} - #{branches.join(', ')}",
          title_link: target_url,
          color: color_for_state(state),
          text: "`#{context}`: #{state} - #{description}",
          mrkdwn_in: ['text'],
          author_name: 'Build status',
        }
      ])
    end

    def process_issue
      return unless %w(opened).include?(action)

      interested_parties = extract_usernames(issue_body)
      interested_parties << "@#{issue_owner}" unless sender == issue_owner
      attachments = [
        {
          fallback: "*Issue*\n*#{repo} - ##{issue_number}: #{issue_title}*\n*#{sender}:* #{issue_body}\nSee More: #{issue_url}",
          title: "#{repo} - ##{issue_number}: #{issue_title}",
          title_link: issue_url,
          author_name: name_for_event(event),
          text: "*#{sender}:* #{issue_body}",
          mrkdwn_in: ['text'],
          fields: [
            {
              title: 'Issue Creator/Owner',
              value: issue_owner,
              short: true,
            }
          ]
        }
      ]
      notify(interested_parties, attachments: attachments)
    end

    def process_issue_comment
      return unless %w(created edited opened).include?(action)

      interested_parties = extract_usernames(comment.body)
      interested_parties << "@#{issue_owner}" unless sender == issue_owner

      attachments = [
        {
          fallback: "*Issue/PR Comment*\n*#{repo} - ##{issue_number}: #{issue_title}*\n*#{sender}:* #{comment.body}\nSee More: #{comment_url}",
          title: "#{repo} - ##{issue_number}: #{issue_title}",
          title_link: comment_url,
          author_name: name_for_event(event),
          text: "*#{sender}:* #{comment.body}",
          mrkdwn_in: ['text'],
          fields: [
            {
              title: 'Issue/PR Owner',
              value: issue_owner,
              short: true,
            }
          ]
        }
      ]

      if comment.path
        attachments[0][:title] += " - #{comment.path}:#{comment.line}"
      end

      if diff_hunk && !ENV['HIDE_DIFFS']
        hunk = diff_hunk.sub(/^.+?\n/, '') # Strip out first line
        attachments << {
          title: diff_path,
          text: "```\n#{hunk}\n```",
          mrkdwn_in: ['text'],
        }
      end
      notify(interested_parties, attachments: attachments)
    end

    def process_commit_comment
      interested_parties = extract_usernames(comment.body)

      attachments = [
        {
          fallback: "*Commit Comment on #{repo}*\n*#{sender}:* #{comment.body}\nSee More: #{comment_url}",
          title: "#{repo}",
          title_link: comment_url,
          author_name: name_for_event(event),
          text: "*#{sender}:* #{comment.body}",
          mrkdwn_in: ['text'],
        }
      ]

      if comment.path
        attachments[0][:title] += " - #{comment.path}:#{comment.line}"
      end

      notify(interested_parties, attachments: attachments)
    end

    def notify(github_users, attachments: [])
      slack_names = github_users.map do |github_user|
        self.class.github_to_slack_mapping[github_user] || github_user
      end.uniq.compact

      send_slack_message({
        channel: SLACK_CHANNEL,
        text: "To: #{slack_names.join(", ")}",
        as_user: true,
        attachments: attachments,
      })
    end

    def self.github_to_slack_mapping
      @github_to_slack_mapping ||= begin
        mapping = {}
        ENV.each do |k, v|
          if k =~ /^SLACK_USERNAME_FOR_(\w+)$/
            mapping["@#{$1.downcase}"] = "@#{v.downcase}"
          end
        end
        mapping
      end
    end

    def send_slack_message(data)
      payload = {
                  channel: SLACK_CHANNEL,
                  as_user: true,
                  parse: 'full',
                }.merge(data)

      puts YAML.dump(payload)
      Excon.post(SLACK_WEBHOOK_URL,
                        headers: {
                          'Content-Type' => 'application/x-www-form-urlencoded',
                        },
                        body: URI.encode_www_form(
                          payload: JSON.dump(payload)
                        ),
                        expects: [200]).body
    rescue Excon::Error::HTTPStatus => ex
      $stderr.puts ex
      $stderr.puts ex.response.body
    end

    def extract_usernames(message)
      message.scan(/(@\w+)\b/).flatten
    end

    def color_for_state(state)
      case state
      when 'success'
        'good'
      when 'error', 'failure'
        'danger'
      when 'pending'
        'warning'
      else
        '#000000'
      end
    end

    def name_for_event(event)
      case event
      when 'issue_comment'
        'Issue comment'
      when 'pull_request_review_comment'
        'Pull request comment'
      when 'pull_request_review'
        'Pull request review'
      when 'commit_comment'
        'Commit comment'
      when 'status'
        'Build status'
      else
        event
      end
    end

    def repo
      data.repository.name
    end

    def sender
      data.sender.login
    end

    def commit_author
      data.commit!.author!.login
    end

    def action
      data.action
    end

    def branches
      (data.branches || []).map(&:name)
    end

    def comment
      data.comment
    end

    def comment_url
      data.comment.html_url
    end

    def diff_hunk
      data.comment.diff_hunk
    end

    def diff_path
      [data.comment.path, data.comment.line].join(":")
    end

    def diff_url
      data.comment.path
    end

    def issue
      data.issue || data.pull_request
    end

    def issue_body
      issue.body
    end

    def issue_number
      issue.number
    end

    def issue_title
      issue.title
    end

    def issue_owner
      issue.owner!.login || issue.user!.login
    end

    def issue_url
      issue.html_url
    end
  end
end
