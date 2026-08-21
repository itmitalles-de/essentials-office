<?php

declare(strict_types=1);

script('appointments', 'common');
script('appointments', 'manage');
style('appointments', 'vendor/simple-business-tokens');
style('appointments', 'appointments');

/** @var \OCP\IL10N $l */
$apiBase = (string)($_['apiBase'] ?? '/apps/appointments/public/v1');
?>
<main id="appointments-manage"
	  class="appointments-public appointments-manage"
	  data-api-base="<?php p($apiBase); ?>">
	<header class="appointments-public-header">
		<img class="appointments-public-logo" src="<?php p(image_path('appointments', 'app.svg')); ?>" alt="">
		<div>
			<p class="appointments-eyebrow"><?php p($l->t('Secure appointment management')); ?></p>
			<h1><?php p($l->t('Manage your appointment')); ?></h1>
			<p class="appointments-muted"><?php p($l->t('This page only gives access to the appointment linked in your email.')); ?></p>
		</div>
	</header>

	<div id="appointments-manage-status" class="appointments-status" role="status" aria-live="polite"></div>

	<div id="appointments-manage-content" class="appointments-manage-grid" hidden>
		<section class="appointments-manage-card" aria-labelledby="appointments-manage-summary-title">
			<div class="appointments-section-heading">
				<div>
					<h2 id="appointments-manage-summary-title"><?php p($l->t('Appointment details')); ?></h2>
					<p id="appointments-manage-booking-number" class="appointments-booking-number"></p>
				</div>
				<span id="appointments-manage-state" class="appointments-state"></span>
			</div>
			<dl id="appointments-manage-summary" class="appointments-summary"></dl>
			<div class="appointments-manage-actions">
				<button id="appointments-manage-ics" type="button"><?php p($l->t('Add to calendar')); ?></button>
				<button id="appointments-manage-export" type="button"><?php p($l->t('Download my data')); ?></button>
				<button id="appointments-manage-reschedule-open" data-testid="manage-reschedule" type="button"><?php p($l->t('Reschedule')); ?></button>
				<button id="appointments-manage-cancel-open" class="appointments-danger" data-testid="manage-cancel" type="button"><?php p($l->t('Cancel appointment')); ?></button>
			</div>
			<p id="appointments-manage-policy" class="appointments-policy" hidden></p>
		</section>

		<section class="appointments-manage-card" aria-labelledby="appointments-manage-contact-title">
			<h2 id="appointments-manage-contact-title"><?php p($l->t('Contact details')); ?></h2>
			<form id="appointments-manage-contact-form" class="appointments-form">
				<div class="appointments-form-grid">
					<label><?php p($l->t('First name')); ?><input name="firstName" type="text" autocomplete="given-name" required maxlength="100"></label>
					<label><?php p($l->t('Last name')); ?><input name="lastName" type="text" autocomplete="family-name" required maxlength="100"></label>
					<label><?php p($l->t('Email')); ?><input name="email" type="email" autocomplete="email" required maxlength="254"></label>
					<label><?php p($l->t('Phone')); ?><input name="phone" type="tel" autocomplete="tel" maxlength="50"></label>
				</div>
				<div class="appointments-form-actions"><button class="primary" type="submit"><?php p($l->t('Update contact details')); ?></button></div>
			</form>
		</section>

		<section id="appointments-manage-reschedule" class="appointments-manage-card appointments-manage-wide" hidden aria-labelledby="appointments-manage-reschedule-title">
			<h2 id="appointments-manage-reschedule-title"><?php p($l->t('Choose a new time')); ?></h2>
			<p id="appointments-manage-timezone" class="appointments-muted"></p>
			<label class="appointments-date-field" for="appointments-manage-date"><?php p($l->t('Date')); ?>
				<input id="appointments-manage-date" type="date">
			</label>
			<div id="appointments-manage-slots-status" class="appointments-inline-status" role="status" aria-live="polite"></div>
			<fieldset class="appointments-choice-group">
				<legend><?php p($l->t('Available times')); ?></legend>
				<div id="appointments-manage-slots" class="appointments-slot-grid"></div>
			</fieldset>
			<div class="appointments-form-actions">
				<button id="appointments-manage-reschedule-close" type="button"><?php p($l->t('Keep current appointment')); ?></button>
				<button id="appointments-manage-reschedule-submit" class="primary" type="button" disabled><?php p($l->t('Confirm new time')); ?></button>
			</div>
		</section>
	</div>

	<dialog id="appointments-cancel-dialog" class="appointments-dialog" aria-labelledby="appointments-cancel-title">
		<form id="appointments-cancel-form" class="appointments-form">
			<div class="appointments-dialog-header">
				<h2 id="appointments-cancel-title"><?php p($l->t('Cancel this appointment?')); ?></h2>
				<button type="button" class="appointments-dialog-close" data-dialog-close aria-label="<?php p($l->t('Close')); ?>">×</button>
			</div>
			<p><?php p($l->t('The reserved time will be released. This action cannot be undone from this page.')); ?></p>
			<div class="appointments-form-actions">
				<button type="button" data-dialog-close><?php p($l->t('Keep appointment')); ?></button>
				<button class="appointments-danger" type="submit"><?php p($l->t('Cancel appointment')); ?></button>
			</div>
		</form>
	</dialog>

	<section id="appointments-manage-unavailable" class="appointments-error-card" hidden aria-labelledby="appointments-manage-unavailable-title">
		<h2 id="appointments-manage-unavailable-title"><?php p($l->t('This management link is no longer available')); ?></h2>
		<p><?php p($l->t('The link may have expired or been revoked. Contact the organization if you need help.')); ?></p>
	</section>
</main>
