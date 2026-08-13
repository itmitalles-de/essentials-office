(function () {
    'use strict';

    const root = document.getElementById('essentialsplus-admin');
    if (!root) {
        return;
    }
    const apiUrl = root.dataset.apiUrl;
    const auditUrl = root.dataset.auditUrl;
    const catalogNode = document.getElementById('essentialsplus-admin-catalog');
    const statusNode = document.getElementById('essentialsplus-admin-status');
    const auditNode = document.getElementById('essentialsplus-admin-audit');

    function text(tag, value, className) {
        const node = document.createElement(tag);
        node.textContent = value;
        if (className) {
            node.className = className;
        }
        return node;
    }

    async function request(url, options) {
        const response = await fetch(url, Object.assign({
            credentials: 'same-origin',
            headers: {
                'Accept': 'application/json',
                'Content-Type': 'application/json',
                'requesttoken': OC.requestToken,
            },
        }, options || {}));
        const payload = await response.json();
        if (!response.ok) {
            throw new Error(payload.error || 'Operation fehlgeschlagen.');
        }
        return payload;
    }

    function actionButton(label, action, module, disabled) {
        const button = text('button', label);
        button.type = 'button';
        button.dataset.action = action;
        button.disabled = Boolean(disabled);
        button.addEventListener('click', async function () {
            button.disabled = true;
            statusNode.textContent = `${module.displayName}: ${label} …`;
            try {
                await request(`${apiUrl}/${encodeURIComponent(module.id)}/${action}`, {method: 'POST', body: '{}'});
                statusNode.textContent = `${module.displayName}: Aktion abgeschlossen.`;
                await loadCatalog();
                await loadAudit();
            } catch (error) {
                statusNode.textContent = `${module.displayName}: ${error.message}`;
                button.disabled = false;
            }
        });
        return button;
    }

    function visibilityControl(module) {
        const container = document.createElement('fieldset');
        container.className = 'essentialsplus-visibility';
        container.appendChild(text('legend', 'Sichtbare Gruppen'));
        module.allowedGroups.forEach(function (group) {
            const label = document.createElement('label');
            const input = document.createElement('input');
            input.type = 'checkbox';
            input.value = group;
            input.checked = module.visibility.includes(group);
            label.appendChild(input);
            label.appendChild(document.createTextNode(` ${group}`));
            container.appendChild(label);
        });
        const save = text('button', 'Gruppen speichern');
        save.type = 'button';
        save.dataset.action = 'visibility';
        save.addEventListener('click', async function () {
            const groups = Array.from(container.querySelectorAll('input:checked')).map((input) => input.value);
            try {
                await request(`${apiUrl}/${encodeURIComponent(module.id)}/visibility`, {
                    method: 'POST',
                    body: JSON.stringify({groups: groups}),
                });
                statusNode.textContent = `${module.displayName}: Sichtbarkeit aktualisiert.`;
                await loadCatalog();
                await loadAudit();
            } catch (error) {
                statusNode.textContent = `${module.displayName}: ${error.message}`;
            }
        });
        container.appendChild(save);
        return container;
    }

    function renderModule(module) {
        const card = document.createElement('article');
        card.className = 'essentialsplus-module';
        card.dataset.moduleId = module.id;
        const heading = document.createElement('div');
        heading.className = 'essentialsplus-module-heading';
        heading.appendChild(text('h4', module.displayName));
        heading.appendChild(text('span', module.state, `essentialsplus-state state-${module.state}`));
        card.appendChild(heading);
        card.appendChild(text('p', module.description));
        const facts = text('dl', '', 'essentialsplus-facts');
        [['Typ', module.type], ['Sollzustand', module.desired ? 'aktiv' : 'inaktiv'], ['Health', module.health.message]].forEach(function (entry) {
            facts.appendChild(text('dt', entry[0]));
            facts.appendChild(text('dd', entry[1]));
        });
        card.appendChild(facts);
        if (module.diagnostics.issues.length) {
            const list = text('ul', '', 'essentialsplus-issues');
            module.diagnostics.issues.forEach((issue) => list.appendChild(text('li', issue)));
            card.appendChild(list);
        }
        card.appendChild(visibilityControl(module));
        const actions = text('div', '', 'essentialsplus-actions');
        actions.appendChild(actionButton('Aktivieren', 'enable', module, module.required || module.state === 'enabled'));
        actions.appendChild(actionButton('Deaktivieren', 'disable', module, module.required || module.state === 'disabled'));
        actions.appendChild(actionButton('Healthcheck', 'doctor', module, false));
        card.appendChild(actions);
        return card;
    }

    async function loadCatalog() {
        const catalog = await request(apiUrl);
        catalogNode.replaceChildren();
        catalog.groups.slice().sort((a, b) => a.order - b.order).forEach(function (group) {
            const section = document.createElement('section');
            section.className = 'essentialsplus-group';
            section.dataset.groupId = group.id;
            section.appendChild(text('h3', group.displayName));
            const grid = text('div', '', 'essentialsplus-grid');
            catalog.modules.filter((module) => module.group === group.id).forEach((module) => grid.appendChild(renderModule(module)));
            if (!grid.childElementCount) {
                grid.appendChild(text('p', 'Keine Module in dieser Gruppe.', 'essentialsplus-empty'));
            }
            section.appendChild(grid);
            catalogNode.appendChild(section);
        });
        statusNode.textContent = `Manifest ${catalog.contractVersion}; ${catalog.modules.length} Module geladen.`;
    }

    async function loadAudit() {
        const payload = await request(auditUrl);
        auditNode.replaceChildren();
        const list = document.createElement('ol');
        payload.entries.forEach(function (entry) {
            const timestamp = new Date(entry.createdAt * 1000).toISOString();
            list.appendChild(text('li', `${timestamp} · ${entry.actor} · ${entry.moduleId} · ${entry.action} · ${entry.outcome}`));
        });
        if (!list.childElementCount) {
            list.appendChild(text('li', 'Noch keine Änderungen protokolliert.'));
        }
        auditNode.appendChild(list);
    }

    Promise.all([loadCatalog(), loadAudit()]).catch(function (error) {
        statusNode.textContent = `Admin-Center konnte nicht geladen werden: ${error.message}`;
    });
}());
