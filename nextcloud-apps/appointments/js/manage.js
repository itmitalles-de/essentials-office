(function () {
	'use strict';

	const root = document.getElementById('appointments-manage');
	if (!root || !window.AppointmentsUI) {
		return;
	}

	const UI = window.AppointmentsUI;
	const apiBase = root.dataset.apiBase.replace(/\/$/, '');
	const nodes = {
		status: document.getElementById('appointments-manage-status'),
		content: document.getElementById('appointments-manage-content'),
		unavailable: document.getElementById('appointments-manage-unavailable'),
		bookingNumber: document.getElementById('appointments-manage-booking-number'),
		state: document.getElementById('appointments-manage-state'),
		summary: document.getElementById('appointments-manage-summary'),
		policy: document.getElementById('appointments-manage-policy'),
		ics: document.getElementById('appointments-manage-ics'),
		exportData: document.getElementById('appointments-manage-export'),
		rescheduleOpen: document.getElementById('appointments-manage-reschedule-open'),
		cancelOpen: document.getElementById('appointments-manage-cancel-open'),
		contactForm: document.getElementById('appointments-manage-contact-form'),
		reschedule: document.getElementById('appointments-manage-reschedule'),
		rescheduleClose: document.getElementById('appointments-manage-reschedule-close'),
		rescheduleSubmit: document.getElementById('appointments-manage-reschedule-submit'),
		date: document.getElementById('appointments-manage-date'),
		timezone: document.getElementById('appointments-manage-timezone'),
		slots: document.getElementById('appointments-manage-slots'),
		slotsStatus: document.getElementById('appointments-manage-slots-status'),
		cancelDialog: document.getElementById('appointments-cancel-dialog'),
		cancelForm: document.getElementById('appointments-cancel-form'),
	};

	const state = {
		token: readAndRemoveToken(),
		appointment: null,
		organization: null,
		permissions: {},
		slot: null,
		slotsRequest: 0,
	};

	function readAndRemoveToken() {
		let token = '';
		if (window.location.hash.length > 1) {
			try {
				token = decodeURIComponent(window.location.hash.slice(1));
			} catch (_error) {
				token = '';
			}
		}
		window.history.replaceState(null, document.title, `${window.location.pathname}${window.location.search}`);
		return token;
	}

	function showStatus(message, kind) {
		nodes.status.textContent = message || '';
		nodes.status.className = `appointments-status${kind ? ` is-${kind}` : ''}`;
	}

	function showUnavailable() {
		nodes.content.hidden = true;
		nodes.unavailable.hidden = false;
		showStatus('');
	}

	function timezone() {
		return (state.organization && state.organization.timezone) || state.appointment.timezone || 'Europe/Berlin';
	}

	function relatedName(value, fallback) {
		return value && (value.displayName || value.name || value.title) || fallback || '—';
	}

	function summaryEntry(term, description) {
		nodes.summary.appendChild(UI.element('dt', {text: term}));
		nodes.summary.appendChild(UI.element('dd', {text: description || '—'}));
	}

	function canUpdateContact() {
		if (!state.appointment) {
			return false;
		}
		const status = String(state.appointment.status || '');
		const terminal = status.startsWith('cancelled_') || status === 'completed' || status === 'no_show';
		return !terminal && state.permissions.canUpdateContact !== false;
	}

	function renderAppointment(payload) {
		state.appointment = payload.appointment || payload;
		state.organization = payload.organization || state.appointment.organization || state.organization || {};
		state.permissions = payload.permissions || payload.actions || state.permissions || {};
		const appointment = state.appointment;
		const contact = appointment.contact || appointment.customer || {};
		nodes.bookingNumber.textContent = appointment.bookingNumber
			? UI.translate('Booking number: {number}', {number: appointment.bookingNumber})
			: '';
		nodes.state.textContent = UI.statusLabel(appointment.status);
		nodes.state.className = `appointments-state state-${appointment.status || 'pending'}`;
		UI.clear(nodes.summary);
		summaryEntry(UI.translate('Service'), relatedName(appointment.service, appointment.serviceName));
		summaryEntry(UI.translate('Date and time'), UI.formatDateTime(appointment.startsAt || appointment.startAt, timezone()));
		summaryEntry(UI.translate('Staff'), relatedName(appointment.staff, appointment.staffName || UI.translate('Any available staff member')));
		summaryEntry(UI.translate('Location'), relatedName(appointment.location, appointment.locationName || UI.translate('Remote appointment')));
		if (appointment.publicInstructions || appointment.bookingInstructions) {
			summaryEntry(UI.translate('Information'), appointment.publicInstructions || appointment.bookingInstructions);
		}
		const form = nodes.contactForm.elements;
		form.firstName.value = contact.firstName || '';
		form.lastName.value = contact.lastName || '';
		form.email.value = contact.email || '';
		form.phone.value = contact.phone || '';
		const cancelled = String(appointment.status || '').startsWith('cancelled_');
		const terminal = cancelled || appointment.status === 'completed' || appointment.status === 'no_show';
		nodes.cancelOpen.hidden = terminal || appointment.cancellationAllowed === false || state.permissions.canCancel === false;
		nodes.rescheduleOpen.hidden = terminal || appointment.rescheduleAllowed === false || state.permissions.canReschedule === false;
		nodes.contactForm.querySelectorAll('input, button[type="submit"]').forEach((control) => { control.disabled = !canUpdateContact(); });
		if (payload.cancellationPolicy) {
			nodes.policy.textContent = payload.cancellationPolicy;
			nodes.policy.hidden = false;
		} else {
			nodes.policy.hidden = true;
		}
		nodes.timezone.textContent = UI.translate('All times are shown in {timezone}.', {timezone: timezone()});
		const today = UI.dateKeyInTimeZone(new Date(), timezone());
		nodes.date.min = today;
		nodes.date.value = today;
		nodes.content.hidden = false;
		nodes.unavailable.hidden = true;
	}

	async function loadAppointment() {
		if (!state.token) {
			showUnavailable();
			return;
		}
		showStatus(UI.translate('Loading appointment…'));
		try {
			const payload = await UI.request(`${apiBase}/manage/view`, {method: 'POST', body: {token: state.token}});
			renderAppointment(payload || {});
			showStatus('');
		} catch (_error) {
			showUnavailable();
		}
	}

	async function updateContact(event) {
		event.preventDefault();
		if (!nodes.contactForm.reportValidity()) {
			return;
		}
		const values = new FormData(nodes.contactForm);
		const submit = nodes.contactForm.querySelector('button[type="submit"]');
		submit.disabled = true;
		try {
			const payload = await UI.request(`${apiBase}/manage/contact`, {
				method: 'POST',
				body: {
					token: state.token,
					contact: {
						firstName: String(values.get('firstName') || '').trim(),
						lastName: String(values.get('lastName') || '').trim(),
						email: String(values.get('email') || '').trim(),
						phone: String(values.get('phone') || '').trim(),
					},
				},
			});
			if (payload) {
				renderAppointment(payload);
			}
			showStatus(UI.translate('Contact details updated.'), 'success');
		} catch (error) {
			showStatus(UI.translate('Contact details could not be updated: {message}', {message: error.message}), 'error');
		} finally {
			submit.disabled = !canUpdateContact();
		}
	}

	async function cancelAppointment(event) {
		event.preventDefault();
		const submit = nodes.cancelForm.querySelector('button[type="submit"]');
		submit.disabled = true;
		try {
			const payload = await UI.request(`${apiBase}/manage/cancel`, {
				method: 'POST', body: {token: state.token},
			});
			UI.closeDialog(nodes.cancelDialog);
			renderAppointment(payload || Object.assign({}, state.appointment, {status: 'cancelled_by_customer'}));
			showStatus(UI.translate('Your appointment has been cancelled.'), 'success');
		} catch (error) {
			showStatus(UI.translate('The appointment could not be cancelled: {message}', {message: error.message}), 'error');
		} finally {
			submit.disabled = false;
		}
	}

	async function loadSlots() {
		const requestId = ++state.slotsRequest;
		state.slot = null;
		nodes.rescheduleSubmit.disabled = true;
		UI.clear(nodes.slots);
		if (!nodes.date.value) {
			return;
		}
		nodes.slotsStatus.textContent = UI.translate('Loading available times…');
		const appointment = state.appointment;
		const requestBody = {
			token: state.token,
			date: nodes.date.value,
			timezone: timezone(),
		};
		if (appointment.locationId || (appointment.location && appointment.location.id)) {
			requestBody.locationId = appointment.locationId || appointment.location.id;
		}
		if (appointment.staffId || (appointment.staff && appointment.staff.id)) {
			requestBody.staffId = appointment.staffId || appointment.staff.id;
		}
		try {
			const payload = await UI.request(`${apiBase}/manage/slots`, {method: 'POST', body: requestBody});
			if (requestId !== state.slotsRequest) {
				return;
			}
			const slots = UI.list(payload && (payload.slots || payload.items || payload));
			nodes.slotsStatus.textContent = slots.length ? '' : UI.translate('No available times were found for this date.');
			slots.forEach(function (slotValue) {
				const slot = typeof slotValue === 'string' ? {startsAt: slotValue} : slotValue;
				const startsAt = slot.startsAt || slot.startAt || slot.start;
				const input = UI.element('input', {type: 'radio', name: 'manage-slot', value: startsAt});
				input.addEventListener('change', function () {
					state.slot = slot;
					nodes.rescheduleSubmit.disabled = false;
				});
				nodes.slots.appendChild(UI.element('label', {className: 'appointments-slot'}, [input, UI.element('span', {text: UI.formatTimeWithZone(startsAt, timezone())})]));
			});
		} catch (error) {
			if (requestId !== state.slotsRequest) {
				return;
			}
			nodes.slotsStatus.textContent = UI.translate('Available times could not be loaded: {message}', {message: error.message});
		}
	}

	async function rescheduleAppointment() {
		if (!state.slot) {
			return;
		}
		nodes.rescheduleSubmit.disabled = true;
		try {
			const startsAt = state.slot.startsAt || state.slot.startAt || state.slot.start;
			const payload = await UI.request(`${apiBase}/manage/reschedule`, {
				method: 'POST', body: {
					token: state.token,
					startsAt: startsAt,
					timezone: timezone(),
					staffId: state.slot.staffId || null,
					locationId: state.slot.locationId || state.appointment.locationId || null,
				},
			});
			renderAppointment(payload || Object.assign({}, state.appointment, {startsAt: startsAt, status: 'rescheduled'}));
			nodes.reschedule.hidden = true;
			showStatus(UI.translate('Your appointment has been rescheduled.'), 'success');
		} catch (error) {
			showStatus(UI.translate('The appointment could not be rescheduled: {message}', {message: error.message}), 'error');
			nodes.rescheduleSubmit.disabled = false;
		}
	}

	async function downloadFromManage(endpoint, filename, accept) {
		try {
			const headers = {'Accept': accept, 'Content-Type': 'application/json'};
			if (window.OC && OC.requestToken) {
				headers.requesttoken = OC.requestToken;
			}
			const response = await fetch(`${apiBase}/manage/${endpoint}`, {
				method: 'POST', credentials: 'same-origin', headers: headers, body: JSON.stringify({token: state.token}),
			});
			if (!response.ok) {
				throw new Error(UI.translate('Download failed.'));
			}
			const blob = await response.blob();
			const url = URL.createObjectURL(blob);
			const link = UI.element('a', {href: url, download: filename});
			document.body.appendChild(link);
			link.click();
			link.remove();
			URL.revokeObjectURL(url);
		} catch (error) {
			showStatus(error.message, 'error');
		}
	}

	UI.bindDialogDismiss(root);
	nodes.contactForm.addEventListener('submit', updateContact);
	nodes.cancelOpen.addEventListener('click', (event) => UI.showDialog(nodes.cancelDialog, event.currentTarget));
	nodes.cancelForm.addEventListener('submit', cancelAppointment);
	nodes.rescheduleOpen.addEventListener('click', function () { nodes.reschedule.hidden = false; nodes.date.focus(); loadSlots(); });
	nodes.rescheduleClose.addEventListener('click', function () { nodes.reschedule.hidden = true; nodes.rescheduleOpen.focus(); });
	nodes.date.addEventListener('change', loadSlots);
	nodes.rescheduleSubmit.addEventListener('click', rescheduleAppointment);
	nodes.ics.addEventListener('click', () => downloadFromManage('ics', 'appointment.ics', 'text/calendar'));
	nodes.exportData.addEventListener('click', () => downloadFromManage('export', 'appointment-data.json', 'application/json'));
	loadAppointment();
}());
