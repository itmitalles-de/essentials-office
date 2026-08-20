<?php

declare(strict_types=1);

script('appointments', 'common');
script('appointments', 'public-booking');
style('appointments', 'appointments');

/** @var \OCP\IL10N $l */
$apiBase = (string)($_['apiBase'] ?? '/apps/appointments/public/v1');
$organizationSlug = (string)($_['organizationSlug'] ?? '');
?>
<main id="appointments-public"
	  class="appointments-public"
	  data-api-base="<?php p($apiBase); ?>"
	  data-organization-slug="<?php p($organizationSlug); ?>">
	<header class="appointments-public-header">
		<img class="appointments-public-logo" id="appointments-public-logo" src="<?php p(image_path('appointments', 'app.svg')); ?>" alt="" hidden>
		<div>
			<p class="appointments-eyebrow"><?php p($l->t('Online booking')); ?></p>
			<h1 id="appointments-public-name"><?php p($l->t('Book an appointment')); ?></h1>
			<p id="appointments-public-description" class="appointments-muted"></p>
			<address id="appointments-public-contact-info" class="appointments-contact-info" hidden></address>
		</div>
	</header>

	<div id="appointments-public-status" class="appointments-status" role="status" aria-live="polite"></div>

	<section id="appointments-booking-shell" class="appointments-booking-shell" hidden aria-labelledby="appointments-public-name">
		<nav aria-label="<?php p($l->t('Booking progress')); ?>">
			<ol class="appointments-progress">
				<li data-progress-step="1" aria-current="step"><span>1</span><?php p($l->t('Service')); ?></li>
				<li data-progress-step="2"><span>2</span><?php p($l->t('Time')); ?></li>
				<li data-progress-step="3"><span>3</span><?php p($l->t('Your details')); ?></li>
				<li data-progress-step="4"><span>4</span><?php p($l->t('Review')); ?></li>
			</ol>
		</nav>

		<form id="appointments-public-form" novalidate>
			<section class="appointments-booking-step" data-booking-step="1" aria-labelledby="appointments-step-service-title">
				<h2 id="appointments-step-service-title"><?php p($l->t('What would you like to book?')); ?></h2>
				<p class="appointments-muted"><?php p($l->t('Choose a service, location, and optionally a specific staff member.')); ?></p>

				<fieldset class="appointments-choice-group">
					<legend><?php p($l->t('Service')); ?></legend>
					<div id="appointments-public-services" class="appointments-choice-grid"></div>
				</fieldset>
				<fieldset id="appointments-public-location-group" class="appointments-choice-group">
					<legend><?php p($l->t('Location or appointment type')); ?></legend>
					<div id="appointments-public-locations" class="appointments-choice-grid"></div>
				</fieldset>
				<fieldset id="appointments-public-staff-group" class="appointments-choice-group">
					<legend><?php p($l->t('Staff member')); ?></legend>
					<div id="appointments-public-staff" class="appointments-choice-grid"></div>
				</fieldset>
			</section>

			<section class="appointments-booking-step" data-booking-step="2" aria-labelledby="appointments-step-time-title" hidden>
				<h2 id="appointments-step-time-title"><?php p($l->t('Choose a date and time')); ?></h2>
				<p id="appointments-public-timezone" class="appointments-muted"></p>
				<label class="appointments-date-field" for="appointments-public-date"><?php p($l->t('Date')); ?>
					<input id="appointments-public-date" name="date" data-testid="public-date" type="date" required>
				</label>
				<div id="appointments-public-slots-status" class="appointments-inline-status" role="status" aria-live="polite"></div>
				<fieldset class="appointments-choice-group">
					<legend><?php p($l->t('Available times')); ?></legend>
					<div id="appointments-public-slots" class="appointments-slot-grid"></div>
				</fieldset>
			</section>

			<section class="appointments-booking-step" data-booking-step="3" aria-labelledby="appointments-step-details-title" hidden>
				<h2 id="appointments-step-details-title"><?php p($l->t('Your contact details')); ?></h2>
				<p class="appointments-muted"><?php p($l->t('We only use these details to manage this appointment.')); ?></p>
				<div class="appointments-form appointments-form-grid">
					<label><?php p($l->t('First name')); ?><input name="firstName" data-testid="public-contact" type="text" autocomplete="given-name" required maxlength="100"></label>
					<label><?php p($l->t('Last name')); ?><input name="lastName" type="text" autocomplete="family-name" required maxlength="100"></label>
					<label><?php p($l->t('Email')); ?><input name="email" type="email" autocomplete="email" required maxlength="254"></label>
					<label><?php p($l->t('Phone')); ?><input name="phone" type="tel" autocomplete="tel" maxlength="50"></label>
				</div>
				<label class="appointments-form-field"><?php p($l->t('Message (optional)')); ?><textarea name="message" rows="4" maxlength="4000"></textarea></label>
				<div id="appointments-public-custom-fields" class="appointments-form appointments-form-grid"></div>
				<div class="appointments-honeypot" aria-hidden="true">
					<label for="appointments-public-website"><?php p($l->t('Website')); ?></label>
					<input id="appointments-public-website" name="website" type="text" tabindex="-1" autocomplete="off">
				</div>
				<input name="bookingStartedAt" type="hidden">
			</section>

			<section class="appointments-booking-step" data-booking-step="4" aria-labelledby="appointments-step-review-title" hidden>
				<h2 id="appointments-step-review-title"><?php p($l->t('Review your appointment')); ?></h2>
				<dl id="appointments-public-review" class="appointments-summary"></dl>
				<label class="appointments-consent">
					<input name="privacyAccepted" type="checkbox" required>
					<span><?php p($l->t('I agree to the privacy policy and the booking terms.')); ?></span>
				</label>
				<p class="appointments-legal-links">
					<a id="appointments-public-privacy" target="_blank" rel="noopener noreferrer" hidden><?php p($l->t('Privacy policy')); ?></a>
					<a id="appointments-public-legal" target="_blank" rel="noopener noreferrer" hidden><?php p($l->t('Legal notice')); ?></a>
				</p>
				<div id="appointments-public-policy" class="appointments-policy" hidden></div>
			</section>

			<div class="appointments-booking-actions">
				<button id="appointments-public-back" type="button" hidden><?php p($l->t('Back')); ?></button>
				<button id="appointments-public-next" class="primary" type="button"><?php p($l->t('Continue')); ?></button>
				<button id="appointments-public-submit" class="primary" data-testid="public-submit" type="submit" hidden><?php p($l->t('Book appointment')); ?></button>
			</div>
		</form>
	</section>

	<section id="appointments-public-confirmation" class="appointments-confirmation" data-testid="booking-confirmation" tabindex="-1" hidden aria-labelledby="appointments-confirmation-title">
		<div class="appointments-confirmation-mark" aria-hidden="true">✓</div>
		<h2 id="appointments-confirmation-title"><?php p($l->t('Your appointment has been booked')); ?></h2>
		<p id="appointments-confirmation-message"></p>
		<dl id="appointments-confirmation-details" class="appointments-summary"></dl>
		<div class="appointments-confirmation-actions">
			<a id="appointments-confirmation-manage" class="button primary" hidden><?php p($l->t('Manage appointment')); ?></a>
			<button id="appointments-confirmation-ics" type="button" hidden><?php p($l->t('Add to calendar')); ?></button>
		</div>
		<p class="appointments-muted"><?php p($l->t('A confirmation email with a secure management link is on its way.')); ?></p>
	</section>
</main>
