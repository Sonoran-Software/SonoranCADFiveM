(() => {
    "use strict";

    const overlay = document.getElementById("overlay");
    const form = document.getElementById("registrationForm");
    const sectionsElement = document.getElementById("sections");
    const titleElement = document.getElementById("formTitle");
    const subtitleElement = document.getElementById("formSubtitle");
    const messageElement = document.getElementById("formMessage");
    const submitButton = document.getElementById("submitButton");
    const cancelButton = document.getElementById("cancelButton");
    const closeButton = document.getElementById("closeButton");
    const resourceName = typeof GetParentResourceName === "function" ? GetParentResourceName() : "sonorancad";
    const MAX_FIELD_LENGTH = 8000;

    const state = {
        session: null,
        template: null,
        prefill: {},
        language: {},
        fields: new Map(),
        selfies: Object.create(null),
        capturingSelfie: false,
        captureSession: null,
        submitting: false,
    };
    const MASK_TOKENS = Object.freeze({
        "#": "[0-9]",
        M: "[0-9]",
        D: "[0-9]",
        Y: "[0-9]",
        S: "[A-Za-z]",
        X: "[A-Za-z0-9]",
    });

    function reverse(value) {
        return Array.from(value).reverse().join("");
    }

    function escapeRegex(character) {
        return character.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    }

    function maskPattern(mask) {
        return Array.from(String(mask || ""), (character) => MASK_TOKENS[character] || escapeRegex(character)).join("");
    }

    function matchesMask(value, mask) {
        if (!mask || !value) return true;
        return new RegExp(`^(?:${maskPattern(mask)})$`).test(String(value));
    }

    function applyMask(value, mask, maskReverse) {
        let source = String(value || "");
        let template = String(mask || "");
        if (!template) return source;
        if (maskReverse) {
            source = reverse(source);
            template = reverse(template);
        }

        let result = "";
        let sourceIndex = 0;
        let consumedToken = false;
        for (const character of template) {
            const tokenPattern = MASK_TOKENS[character];
            if (!tokenPattern) {
                if (source[sourceIndex] === character) sourceIndex += 1;
                if (consumedToken || sourceIndex < source.length) result += character;
                continue;
            }

            const token = new RegExp(`^${tokenPattern}$`);
            while (sourceIndex < source.length && !token.test(source[sourceIndex])) sourceIndex += 1;
            if (sourceIndex >= source.length) break;
            result += source[sourceIndex];
            sourceIndex += 1;
            consumedToken = true;
        }
        return maskReverse ? reverse(result) : result;
    }

    function isFlagField(field, section) {
        return String(field.type || "") === "checkboxes" ||
            (Number(section && section.category) === 1 && field.data && Array.isArray(field.data.flags));
    }

    function requiresPlayerValue(field) {
        const type = String(field.type || "");
        return !!field.isRequired && !field.readOnly && !field.isSupervisor && type !== "label" && type !== "id" &&
            !type.startsWith("UNIT_");
    }

    async function nui(endpoint, body = {}) {
        const response = await fetch(`https://${resourceName}/${endpoint}`, {
            method: "POST",
            headers: { "Content-Type": "application/json; charset=UTF-8" },
            body: JSON.stringify(body),
        });
        return response.json();
    }

    function showMessage(message) {
        messageElement.textContent = message || "";
        messageElement.classList.toggle("is-visible", !!message);
    }

    function setSubmitting(submitting) {
        state.submitting = submitting;
        submitButton.disabled = submitting;
        cancelButton.disabled = submitting;
        closeButton.disabled = submitting;
        submitButton.textContent = submitting ? "Submitting..." : (state.language.submit || "Register Character");
    }

    function close() {
        overlay.classList.remove("is-open");
        overlay.setAttribute("aria-hidden", "true");
        state.session = null;
        setSubmitting(false);
        showMessage("");
        state.template = null;
        state.prefill = {};
        state.language = {};
        state.selfies = Object.create(null);
        state.capturingSelfie = false;
        state.captureSession = null;
        state.fields.clear();
        sectionsElement.replaceChildren();
    }

    function currentValue(uid) {
        const entry = state.fields.get(uid);
        if (!entry) return "";
        if (entry.type === "checkboxes") {
            return Array.from(entry.element.querySelectorAll("input:checked"), (input) => input.value);
        }
        return entry.element.value || "";
    }

    function dependencyMatches(dependency) {
        if (!dependency || !dependency.fid) return true;
        const actual = currentValue(dependency.fid);
        const acceptable = Array.isArray(dependency.acceptableValues) ? dependency.acceptableValues.map(String) : [];
        const matched = Array.isArray(actual)
            ? actual.some((value) => acceptable.includes(String(value)))
            : acceptable.includes(String(actual));
        return String(dependency.type || "").toUpperCase() === "NOTEQUAL" ? !matched : matched;
    }

    function updateDependencies() {
        for (const section of state.template.sections || []) {
            const sectionElement = document.querySelector(`[data-section-index="${section.__index}"]`);
            if (!sectionElement) continue;
            const sectionVisible = dependencyMatches(section.dependency);
            sectionElement.hidden = !sectionVisible;
            for (const field of section.fields || []) {
                const entry = state.fields.get(field.uid);
                if (entry && entry.wrapper) {
                    entry.wrapper.hidden = !sectionVisible || !dependencyMatches(field.dependency);
                }
            }
        }
    }

    function fieldLabel(field) {
        const label = document.createElement("label");
        label.className = "field-label";
        label.textContent = field.label || field.uid || "Field";
        if (requiresPlayerValue(field)) {
            const required = document.createElement("span");
            required.className = "required";
            required.textContent = "*";
            required.setAttribute("aria-label", "required");
            label.appendChild(required);
        }
        return label;
    }

    function initialValue(field, effectiveType = field.type) {
        if (Object.prototype.hasOwnProperty.call(state.prefill, field.uid)) return state.prefill[field.uid];
        if (effectiveType === "checkboxes") return field.data && Array.isArray(field.data.flags) ? field.data.flags : [];
        if (field.type === "random" && !field.value && field.mask) {
            const letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
            const alphanumeric = `${letters}0123456789`;
            return String(field.mask).replace(/[#SX]/g, (token) => {
                const source = token === "#" ? "0123456789" : (token === "S" ? letters : alphanumeric);
                const random = new Uint32Array(1);
                crypto.getRandomValues(random);
                return source[random[0] % source.length];
            });
        }
        return field.value == null ? "" : String(field.value);
    }

    function applyMaskConstraint(input, field) {
        const mask = String(field.mask || "");
        if (!mask) return;
        input.setAttribute("pattern", maskPattern(mask));
        input.maxLength = Array.from(mask).length;
        input.title = `Use the format ${mask}.`;
        if (!/[SX]/.test(mask)) input.inputMode = "numeric";
        const enforce = () => {
            const masked = applyMask(input.value, mask, !!field.maskReverse);
            if (input.value !== masked) input.value = masked;
        };
        enforce();
        input.addEventListener("input", enforce);
    }

    function makeInput(field) {
        const type = String(field.type || "text");
        if (type === "textarea") {
            const input = document.createElement("textarea");
            input.className = "control";
            input.value = initialValue(field);
            input.maxLength = MAX_FIELD_LENGTH;
            applyMaskConstraint(input, field);
            return input;
        }
        if (type === "select" || type === "status") {
            const select = document.createElement("select");
            select.className = "control";
            const blank = document.createElement("option");
            blank.value = "";
            blank.textContent = "Select...";
            select.appendChild(blank);
            const fieldOptions = Array.isArray(field.options) ? field.options : [];
            const options = type === "status" && !fieldOptions.length
                ? [{ value: "0", label: "Pending" }, { value: "1", label: "Approved" }, { value: "2", label: "Rejected" }]
                : fieldOptions.map((value) => ({ value: String(value), label: String(value) }));
            for (const optionData of options) {
                const option = document.createElement("option");
                option.value = optionData.value;
                option.textContent = optionData.label;
                select.appendChild(option);
            }
            select.value = initialValue(field);
            return select;
        }
        const input = document.createElement("input");
        input.className = "control";
        input.type = type === "time" ? "time" : "text";
        input.value = initialValue(field);
        input.maxLength = MAX_FIELD_LENGTH;
        input.placeholder = field.placeholder || field.mask || "";
        applyMaskConstraint(input, field);
        return input;
    }

    function makeCheckboxes(field) {
        const container = document.createElement("div");
        container.className = "checkbox-list";
        const initial = initialValue(field, "checkboxes");
        const selected = new Set((Array.isArray(initial) ? initial : []).map(String));
        const options = Array.isArray(field.options) ? field.options : [];
        for (const optionValue of options) {
            const option = document.createElement("label");
            option.className = "checkbox-option";
            const checkbox = document.createElement("input");
            checkbox.type = "checkbox";
            checkbox.value = String(optionValue);
            checkbox.checked = selected.has(String(optionValue));
            checkbox.disabled = !!field.readOnly;
            option.append(checkbox, document.createTextNode(String(optionValue)));
            container.appendChild(option);
        }
        return container;
    }

    function cameraIcon() {
        const wrapper = document.createElement("div");
        wrapper.innerHTML = '<svg class="camera-icon" viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M9 3 7.2 5H4a2 2 0 0 0-2 2v11a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2h-3.2L15 3H9Zm3 14.5A4.5 4.5 0 1 1 12 8a4.5 4.5 0 0 1 0 9.5Zm0-2A2.5 2.5 0 1 0 12 10a2.5 2.5 0 0 0 0 5.5Z"/></svg>';
        return wrapper.firstElementChild;
    }

    function renderSelfieButton(field) {
        const button = document.createElement("button");
        button.type = "button";
        button.className = "selfie-button";
        button.setAttribute("aria-label", `${field.label || "Image"}: ${state.language.selfieAction || "Click to take a selfie"}`);

        const renderPrompt = () => {
            button.replaceChildren();
            const prompt = document.createElement("span");
            prompt.className = "selfie-prompt";
            prompt.appendChild(cameraIcon());
            const action = document.createElement("span");
            action.className = "selfie-action";
            action.textContent = state.language.selfieAction || "Click to take a selfie";
            const hint = document.createElement("span");
            hint.className = "selfie-hint";
            hint.textContent = state.language.selfieHint || "Your current character portrait will be attached to this CAD record.";
            prompt.append(action, hint);
            button.appendChild(prompt);
        };
        renderPrompt();

        button.addEventListener("click", async () => {
            if (state.submitting || state.capturingSelfie) return;
            const session = state.session;
            state.capturingSelfie = true;
            state.captureSession = session;
            button.disabled = true;
            showMessage("");
            try {
                const result = await nui("civregTakeSelfie");
                if (!result.ok || !result.image) throw new Error(result.error || "Selfie capture failed.");
                if (state.session !== session) return;
                state.selfies[field.uid] = result.image;
                const preview = document.createElement("img");
                preview.className = "selfie-preview";
                preview.src = result.image;
                preview.alt = `${field.label || "Character"} selfie preview. Click to retake.`;
                button.replaceChildren(preview);
            } catch (error) {
                if (state.session === session) {
                    showMessage(error.message || "Selfie capture failed.");
                    renderPrompt();
                }
            } finally {
                if (state.captureSession === session) {
                    state.capturingSelfie = false;
                    state.captureSession = null;
                }
                button.disabled = !!field.readOnly;
            }
        });
        return button;
    }

    function renderField(field, section) {
        if (!field || !field.uid || field.isSupervisor) return null;
        const type = String(field.type || "text");
        const effectiveType = isFlagField(field, section) ? "checkboxes" : type;
        const wrapper = document.createElement("div");
        wrapper.className = "field";
        wrapper.style.setProperty("--field-size", String(Math.max(1, Math.min(12, Number(field.size) || 12))));
        wrapper.dataset.uid = field.uid;

        if (type === "label") {
            const text = document.createElement("p");
            text.className = "field-description";
            text.textContent = field.value || field.label || "";
            wrapper.appendChild(text);
            state.fields.set(field.uid, { type, element: text, wrapper, field });
            return wrapper;
        }

        wrapper.appendChild(fieldLabel(field));
        let control;
        if (type === "image") {
            control = renderSelfieButton(field);
            control.disabled = !!field.readOnly;
        } else if (effectiveType === "checkboxes") {
            control = makeCheckboxes(field);
        } else {
            control = makeInput(field);
            control.disabled = !!field.readOnly || type === "id" || type === "random" || type.startsWith("UNIT_");
        }
        control.addEventListener("input", updateDependencies);
        control.addEventListener("change", updateDependencies);
        wrapper.appendChild(control);
        if (field.readOnly) {
            const note = document.createElement("p");
            note.className = "field-description";
            note.textContent = "This field is filled automatically.";
            wrapper.appendChild(note);
        }
        state.fields.set(field.uid, { type: effectiveType, element: control, wrapper, field });
        return wrapper;
    }

    function renderForm() {
        sectionsElement.replaceChildren();
        state.fields.clear();
        (state.template.sections || []).forEach((section, sectionIndex) => {
            section.__index = sectionIndex;
            const sectionElement = document.createElement("section");
            sectionElement.className = "form-section";
            sectionElement.dataset.sectionIndex = String(sectionIndex);
            const heading = document.createElement("h2");
            heading.className = "section-title";
            heading.textContent = section.label || "Character Information";
            const grid = document.createElement("div");
            grid.className = "field-grid";
            for (const field of section.fields || []) {
                const rendered = renderField(field, section);
                if (rendered) grid.appendChild(rendered);
            }
            if (grid.childElementCount) {
                sectionElement.append(heading, grid);
                sectionsElement.appendChild(sectionElement);
            }
        });
        updateDependencies();
    }

    function collectValues() {
        const values = Object.create(null);
        for (const [uid, entry] of state.fields) {
            if (entry.wrapper.hidden || entry.type === "image" || entry.type === "label") continue;
            if (entry.type === "checkboxes") values[uid] = { flags: currentValue(uid) };
            else values[uid] = currentValue(uid);
        }
        return values;
    }

    function collectSelfies() {
        const selfies = Object.create(null);
        for (const [uid, image] of Object.entries(state.selfies)) {
            const entry = state.fields.get(uid);
            if (entry && entry.type === "image" && !entry.field.readOnly && !entry.wrapper.hidden) {
                selfies[uid] = image;
            }
        }
        return selfies;
    }

    function validate() {
        for (const [uid, entry] of state.fields) {
            if (entry.wrapper.hidden) continue;
            const value = entry.type === "image" ? state.selfies[uid] : currentValue(uid);
            const empty = (Array.isArray(value) && !value.length) ||
                (!Array.isArray(value) && !String(value || "").trim());
            if (requiresPlayerValue(entry.field) && empty) {
                entry.wrapper.scrollIntoView({ behavior: "smooth", block: "center" });
                return `${entry.field.label || uid} is required.`;
            }
            if (!empty && !Array.isArray(value) && !matchesMask(value, entry.field.mask)) {
                entry.wrapper.scrollIntoView({ behavior: "smooth", block: "center" });
                return `${entry.field.label || uid} must match the format ${entry.field.mask}.`;
            }
        }
        return null;
    }

    function open(payload) {
        state.session = payload.session;
        state.template = payload.template || { sections: [] };
        state.prefill = payload.prefill || {};
        state.language = payload.language || {};
        state.selfies = Object.create(null);
        state.capturingSelfie = false;
        state.captureSession = null;
        titleElement.textContent = state.language.title || state.template.name || "Character Registration";
        subtitleElement.textContent = state.language.subtitle || "Complete the live CAD character form below.";
        cancelButton.textContent = state.language.cancel || "Cancel";
        setSubmitting(false);
        showMessage("");
        renderForm();
        overlay.classList.add("is-open");
        overlay.setAttribute("aria-hidden", "false");
    }

    form.addEventListener("submit", async (event) => {
        event.preventDefault();
        if (state.submitting) return;
        if (state.capturingSelfie) {
            showMessage("Wait for the selfie capture to finish before submitting.");
            return;
        }
        const validationError = validate();
        if (validationError) {
            showMessage(validationError);
            return;
        }
        setSubmitting(true);
        showMessage("");
        try {
            const result = await nui("civregSubmit", {
                session: state.session,
                values: collectValues(),
                selfies: collectSelfies(),
            });
            if (!result.ok) throw new Error("The form could not be submitted.");
        } catch (error) {
            setSubmitting(false);
            showMessage(error.message || "The form could not be submitted.");
        }
    });

    async function requestClose() {
        if (state.submitting) return;
        close();
        try { await nui("civregClose"); } catch (_) {}
    }

    cancelButton.addEventListener("click", requestClose);
    closeButton.addEventListener("click", requestClose);
    document.addEventListener("keydown", (event) => {
        if (event.key === "Escape" && overlay.classList.contains("is-open")) requestClose();
    });

    window.addEventListener("message", (event) => {
        const message = event.data;
        if (!message || !message.civreg) return;
        if (message.action === "open" && message.payload) open(message.payload);
        else if (message.action === "close") close();
        else if (message.action === "result" && message.payload && !message.payload.success) {
            setSubmitting(false);
            showMessage(message.payload.message || "Character registration failed.");
        }
    });
})();
