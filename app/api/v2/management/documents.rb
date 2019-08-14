
# frozen_string_literal: true

module API::V2
  module Management
    class Documents < Grape::API

      desc 'Documents related routes'
      resource :documents do
        desc 'Push documents to barong DB' do
          @settings[:scope] = :write_documents
          success API::V2::Entities::UserWithProfile
        end

        params do
          requires :uid, type: String, allow_blank: false, desc: 'User uid'
          requires :doc_type,
                   type: String,
                   allow_blank: false,
                   desc: 'Document type'
          requires :doc_number,
                   type: String,
                   allow_blank: false,
                   desc: 'Document number'
          requires :upload,
                   desc: 'Array of Rack::Multipart::UploadedFile'
          optional :doc_expire,
                   type: { value: Date, message: "management.documents.expire_not_a_date" },
                   allow_blank: false,
                   desc: 'Document expiration date'
          optional :metadata, type: Hash, desc: 'Any key:value pairs'
        end

        post do
          user = User.find_by!(params[:uid])

          params[:upload].each do |file|
            doc = user.documents.new(declared(params).except(:upload, :uid).merge(upload: file))

            error!(doc.errors.full_messages.to_sentence, 422) unless doc.save
          end

          status 201
        end
      end
    end
  end
end
