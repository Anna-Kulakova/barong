# frozen_string_literal: true

describe API::V2::Identity::Sessions do
  include ActiveSupport::Testing::TimeHelpers
  let!(:create_member_permission) do
    create :permission,
           role: 'member'
  end
  before do
    allow(Barong::CaptchaPolicy.config).to receive_messages(disabled: false, re_captcha: true, geetest: false)
  end

  describe 'POST /api/v2/identity/sessions' do
    let!(:email) { 'user@gmail.com' }
    let!(:password) { 'testPassword111' }
    let(:uri) { '/api/v2/identity/sessions' }
    subject!(:user) do
      create :user,
             email: email,
             password: password,
             password_confirmation: password
    end
    let(:otp_enabled) { false }

    context 'With valid params' do
      let(:do_request) { post uri, params: params }
      let(:session_expire_time) do
        Barong::App.config.session_expire_time.to_i.seconds
      end
      let(:check_session) do
        get '/api/v2/identity/sessions/authorize/resource/users/me'
      end
      let(:params) do
        {
          email: email,
          password: password
        }
      end

      let(:captcha_response) { nil }
      let(:valid_response) { 'valid' }
      let(:invalid_response) { 'invalid' }

      before do
        allow_any_instance_of(CaptchaService::RecaptchaVerifier).to receive(:verify_recaptcha)
          .with(model: user,
                skip_remote_ip: true,
                response: valid_response) { true }

        allow_any_instance_of(CaptchaService::RecaptchaVerifier).to receive(:verify_recaptcha)
          .with(model: user,
                skip_remote_ip: true,
                response: invalid_response) { raise StandardError }
      end

      context 'when captcha response is blank' do
        let(:params) do
          {
            email: email,
            password: password,
            captcha_response: captcha_response
          }
        end
      end

      context 'when captcha response is not valid' do
        let(:params) do
          {
            email: email,
            password: password,
            captcha_response: invalid_response
          }
        end

        before do
          expect_any_instance_of(CaptchaService::RecaptchaVerifier).to receive(:verify_recaptcha) { false }
        end

        it 'renders an error' do
          do_request
          expect(json_body[:errors]).to eq(["identity.captcha.verification_failed"])
          expect_status_to_eq 422
        end
      end

      context 'when captcha response is valid' do
        let(:params) do
          {
            email: email,
            password: password,
            captcha_response: valid_response
          }
        end

        before do
          expect_any_instance_of(CaptchaService::RecaptchaVerifier).to receive(:verify_recaptcha) { true }
        end
      end
    end

    context 'With Invalid params' do
      context 'Checks current credentials and returns error' do
        it 'when email, password is missing' do
          post uri
          expect_body.to eq(errors: ["identity.session.missing_email", "identity.session.missing_password"])
          expect(response.status).to eq(422)
        end

        it 'when password is missing' do
          post uri, params: { email: email }
          expect_body.to eq(errors: ["identity.session.missing_password"])
          expect(response.status).to eq(422)
        end

        context 'when Password is wrong' do
          it 'returns errror' do
            post uri, params: { email: email, password: 'password' }
            expect_body.to eq(errors: ["identity.session.invalid_params"])
            expect(response.status).to eq(401)
          end
        end
      end
    end

    context 'User state related errors' do
      context 'When user is banned' do
        let!(:banned_email) { 'email@random.com' }
        let!(:user_banned) do
          create :user,
                 email: banned_email,
                 password: password,
                 password_confirmation: password,
                 state: 'banned'
        end

        it 'returns error on banned user' do
          post uri, params: { email: banned_email, password: password }
          expect_body.to eq(errors: ["identity.session.banned"])
          expect(response.status).to eq(401)
        end
      end

      let!(:pending_email) { 'pendingemail@random.com' }
      let!(:user_pending) do
        create :user,
               email: pending_email,
               password: password,
               password_confirmation: password,
               state: 'pending'
      end

      context 'Default pending_login_allowed policy (false)' do
        it 'returns error on non-active user' do
          user_pending.update(state: 'not-active')
          post uri, params: { email: pending_email, password: password }
          expect_body.to eq(errors: ["identity.session.not_active"])
          expect(response.status).to eq(401)
        end

        it 'returns error on pending user' do
          user_pending.update(state: 'pending')
          expect(user_pending.state).to eq('pending')

          post uri, params: { email: pending_email, password: password }
          expect_body.to eq(errors: ["identity.session.not_active"])
          expect(response.status).to eq(401)
        end
      end

      context 'When pending_login_allowed set to TRUE' do
        before do
          allow(Barong::App.config).to receive(:pending_login_allowed).and_return(true)
        end

        it 'returns 200 for pending user' do
          post uri, params: { email: pending_email, password: password }
          expect(response.status).to eq(200)
        end
      end
    end
  end

  describe 'DELETE /api/v2/identity/sessions' do
    let!(:email) { 'user@gmail.com' }
    let!(:password) { 'testPassword111' }
    let(:uri) { '/api/v2/identity/sessions' }
    let(:params) do
      {
        email: email,
        password: password
      }
    end
    subject!(:user) do
      create :user,
             email: email,
             password: password,
             password_confirmation: password
    end
    context 'With valid session' do
      let(:do_create_session_request) { post uri, params: params }
      let(:do_delete_session_request) { delete uri }

      it 'Deletes session' do
        do_create_session_request
        expect(session[:uid]).to eq(user.uid)

        do_delete_session_request
        expect(session[:uid]).to eq(nil)
      end

      it "return invalid set-cookie header on #logout" do
        do_create_session_request
        expect(session[:uid]).to eq(user.uid)

        do_delete_session_request
        expect(response.status).to eq(200)
        expect(response.headers['Set-Cookie']).not_to be_nil
        expect(response.headers['Set-Cookie']).to include "_session_id"
      end
    end
  end
end
