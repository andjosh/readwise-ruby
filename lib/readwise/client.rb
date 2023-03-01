require 'json'
require 'net/http'
require_relative 'book'
require_relative 'highlight'
require_relative 'tag'

module Readwise
  class Client
    class Error < StandardError; end

    def initialize(token: nil)
      raise ArgumentError unless token
      @token = token.to_s
    end

    def create_highlight(highlight:)
      create_highlights([highlight])
    end

    def create_highlights(highlights: [])
      raise NotImplementedError
    end

    def export(updated_after: nil, book_ids: [])
      resp = export_page(updated_after: updated_after, book_ids: book_ids)
      next_page_cursor = resp[:next_page_cursor]
      results = resp[:results]
      while next_page_cursor
        resp = export_page(updated_after: updated_after, book_ids: book_ids, page_cursor: next_page_cursor)
        results.concat(resp[:results])
        next_page_cursor = resp[:next_page_cursor]
      end
      results.sort_by(&:highlighted_at_time)
    end

    def save(params)
      uri = URI("https://readwise.io/api/v3/save")
      headers = {
        "Authorization": "Token #{@token}",
        "Content-Type": "application/json"
      }
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      response = http.post(uri.path, params.to_json, headers)
      response_code = Integer(response.code)
      if response_code == 429
        retry_after = Integer(response.fetch("Retry-After"))
        raise Error, "Rate limited exceeded, retry after #{retry_after} seconds"
      elsif response_code >= 400
        raise Error, "Save request failed"
      else
        response.body
      end
    end

    private

    def export_page(page_cursor: nil, updated_after: nil, book_ids: [])
      parsed_body = get_export_page(page_cursor: page_cursor, updated_after: updated_after, book_ids: book_ids)
      results = parsed_body.dig('results').map do |item|
        Book.new(
          asin: item['asin'],
          author: item['author'],
          book_id: item['user_book_id'].to_s,
          category: item['category'],
          cover_image_url: item['cover_image_url'],
          note: item['document_note'],
          readable_title: item['readable_title'],
          readwise_url: item['readwise_url'],
          source: item['source'],
          source_url: item['source_url'],
          tags: item['book_tags'].map do |tag|
            Tag.new(
              tag_id: tag['id'].to_s,
              name: tag['name']
            )
          end,
          title: item['title'],
          unique_url: item['unique_url'],
          highlights: item['highlights'].map do |highlight|
            Highlight.new(
              book_id: highlight['book_id'].to_s,
              color: highlight['color'],
              created_at: highlight['created_at'],
              end_location: highlight['end_location'],
              external_id: highlight['external_id'],
              highlight_id: highlight['id'].to_s,
              highlighted_at: highlight['highlighted_at'],
              is_discard: highlight['is_discard'],
              is_favorite: highlight['is_favorite'],
              location: highlight['location'],
              location_type: highlight['location_type'],
              note: highlight['note'],
              readwise_url: highlight['readwise_url'],
              tags: highlight['tags'].map do |tag|
                Tag.new(
                  tag_id: tag['id'].to_s,
                  name: tag['name']
                )
              end,
              text: highlight['text'],
              updated_at: highlight['updated_at'],
              url: highlight['url'],
            )
          end
        )
      end
      {
        results: results,
        next_page_cursor: parsed_body.dig('nextPageCursor')
      }
    end

    def get_export_page(page_cursor: nil, updated_after: nil, book_ids: [])
      params = {}
      params['updatedAfter'] = updated_after if updated_after
      params['ids'] = book_ids if book_ids.any?
      params['pageCursor'] = page_cursor if page_cursor
      url = 'https://readwise.io/api/v2/export/?' + URI.encode_www_form(params)
      export_uri = URI.parse(url)
      export_req = Net::HTTP::Get.new(export_uri)
      export_req['Authorization'] = "Token #{@token}"
      export_res = Net::HTTP.start(export_uri.hostname, export_uri.port, use_ssl: true) do |http|
        http.request(export_req)
      end
      raise Error, 'Export request failed' unless export_res.is_a?(Net::HTTPSuccess)

      JSON.parse(export_res.body)
    end
  end
end
